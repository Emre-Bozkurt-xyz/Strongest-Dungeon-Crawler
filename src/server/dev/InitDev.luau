--!strict
-- Server dev-only hooks (testing, debug, demo setup).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugConfig = require(ReplicatedStorage.Shared.Debug.DebugConfig)
local AttributeTypes = require(ReplicatedStorage.Shared.AttributeTypes)
local PercentOfStatModifier = require(ReplicatedStorage.Shared.Modifiers.PercentOfStatModifier)
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)
local SkillQueryTypes = require(ReplicatedStorage.Shared.skills.SkillQueryTypes)

local Dev = {}
local devTuneRemote: RemoteEvent? = nil
local devTuneConn: RBXScriptConnection? = nil

local function ensureDevTuneRemote(): RemoteEvent
	if devTuneRemote and devTuneRemote.Parent then
		return devTuneRemote
	end
	local existing = ReplicatedStorage:FindFirstChild("DevTuneRemote")
	if existing and existing:IsA("RemoteEvent") then
		devTuneRemote = existing
		return existing
	end
	local remote = Instance.new("RemoteEvent")
	remote.Name = "DevTuneRemote"
	remote.Parent = ReplicatedStorage
	devTuneRemote = remote
	return remote
end

function Dev.start(ctx)
	DebugConfig.setMany({
		sessionPerf = false,
		skills = true,
		session = true,
		projectiles = true,
	})

	local remote = ensureDevTuneRemote()
	if not devTuneConn then
		devTuneConn = remote.OnServerEvent:Connect(function(player: Player, rawCommand: any)
			if type(rawCommand) ~= "string" then
				return
			end
			-- Studio-only relay: lets Client Command Bar trigger tuning commands
			-- by firing this remote from client context.
			remote:FireClient(player, rawCommand)
		end)
	end

	local g: any = _G
	g.DevTune = function(commandOrPlayer: any, maybeCommand: any)
		if
			typeof(commandOrPlayer) == "Instance"
			and commandOrPlayer:IsA("Player")
			and type(maybeCommand) == "string"
		then
			remote:FireClient(commandOrPlayer, maybeCommand)
			return
		end
		if type(commandOrPlayer) == "string" then
			remote:FireAllClients(commandOrPlayer)
			return
		end
		warn('[DevTune] Usage: _G.DevTune("set Camera.baseline.shoulderBack 5.2")')
		warn('[DevTune]    or: _G.DevTune(player, "set Camera.baseline.shoulderBack 5.2")')
	end

	-- Moves a player's pool, for checking the vitals UI without a fight. Positive adds, negative
	-- removes: ServerStorage.DevPool:Fire(player, "Health", -40). An instance rather than a _G
	-- function because the Studio command bar and MCP scripts do not share this script's _G.
	local devPool = Instance.new("BindableEvent")
	devPool.Name = "DevPool"
	devPool.Parent = game:GetService("ServerStorage")
	devPool.Event:Connect(function(player: Player, pool: string, delta: number)
		local registrar = require(script.Parent.Parent.Services.Registrar)
		local statsManager = require(script.Parent.Parent.Stats.StatsManager)
		local playerId = registrar.getPlayerId(player)
		if not playerId then
			warn("[DevPool] No playerId for", player)
			return
		end
		if delta >= 0 then
			statsManager.addToPool(playerId, pool :: any, delta)
		else
			statsManager.removeFromPool(playerId, pool :: any, -delta)
		end
	end)

	-- Drops the first `count` bag items in front of the player, for checking the loot labels:
	-- ServerStorage.DevDrop:Fire(player, 3).
	local devDrop = Instance.new("BindableEvent")
	devDrop.Name = "DevDrop"
	devDrop.Parent = game:GetService("ServerStorage")
	devDrop.Event:Connect(function(player: Player, count: number)
		local registrar = require(script.Parent.Parent.Services.Registrar)
		local inventoryService = require(script.Parent.Parent.Inventory.InventoryService)
		local playerId = registrar.getPlayerId(player)
		local inventory = playerId and inventoryService.getInventory(playerId)
		if not playerId or not inventory then
			warn("[DevDrop] No inventory for", player)
			return
		end
		local dropped = 0
		for slot = 1, inventory.capacity do
			local uid = inventory.slots[slot]
			if uid and dropped < count then
				inventoryService.dropItem(playerId, uid)
				dropped += 1
			end
		end
	end)
end

function Dev.onPlayerReady(player: Player, character: Model)
	local registrar = require(script.Parent.Parent.Services.Registrar)
	local statsManager = require(script.Parent.Parent.Stats.StatsManager)
	local attributesManager = require(script.Parent.Parent.Stats.AttributesManager)
	local skillsManager = require(script.Parent.Parent.SkillsFramework.SkillsManager)
	local inventoryService = require(script.Parent.Parent.Inventory.InventoryService)
	local skillModifierRegistry = require(script.Parent.Parent.Stats.SkillModifierRegistry)
	local npcSpawner = require(script.Parent.Parent.NPCService.NPCSpawner)
	local testModifiers = require(script.Parent.Parent.SkillsFramework.TestModifiers)

	local playerId = registrar.getPlayerId(player)

	if not playerId then
		warn("Dev.onPlayerReady: No playerId for player", player.Name)
		return
	end

	npcSpawner.spawn("Dummy", {
		position = Vector3.new(90, 5, 0),
	})
	npcSpawner.spawn("Slime", {
		position = Vector3.new(100, 5, 0),
	})

	-- Phase B: BasicAttack replaces Punch as the bound offensive primitive (D6, adaptive per
	-- current weapon). Punch stays granted only implicitly via NPCs/tests; players get BasicAttack.
	skillsManager.addSkill(playerId, "BasicAttack")
	skillsManager.addSkill(playerId, "TripleStrike")
	skillsManager.addSkill(playerId, "Dash")
	skillsManager.addSkill(playerId, "DodgeRoll")
	skillsManager.addSkill(playerId, "ManaBall")
	skillsManager.addSkill(playerId, "CascadingManaBalls")

	inventoryService.addItem(playerId, "mana_potion", 5)
	inventoryService.addItem(playerId, "iron_sword", 1, { rarity = "normal" })
	inventoryService.addItem(playerId, "iron_sword", 1, { rarity = "magic" })
	-- Two of each one-hander so dual-wield hand alternation can be exercised.
	inventoryService.addItem(playerId, "crooked_wand", 1, { rarity = "magic" })
	inventoryService.addItem(playerId, "crooked_wand", 1, { rarity = "normal" })
	inventoryService.addItem(playerId, "iron_dagger", 1, { rarity = "magic" })
	inventoryService.addItem(playerId, "iron_dagger", 1, { rarity = "normal" })
	inventoryService.addItem(playerId, "round_shield", 1, { rarity = "magic" })
	inventoryService.addItem(playerId, "leather_chest", 1, { rarity = "normal" })

	statsManager.addModifier(
		playerId,
		StatTypes.StaticStats.ManaRegeneration,
		PercentOfStatModifier.new({
			value = 0.1, -- 10% of max mana
			source_id = "mana_regen_test",
			targetStat = StatTypes.PoolStats.Mana,
			description = "Base mana regeneration",
		})
	)

	local meleeDoubleCost: any = {
		id = "Test_MeleeManaDouble",
		priority = 100,
		matches = function(ctx: SkillQueryTypes.SkillQueryContext): boolean
			if ctx.event ~= "resolveSkillCost" then
				return false
			end
			local base = ctx.base
			if base.resource ~= StatTypes.PoolStats.Stamina then
				return false
			end
			local tags = ctx.tags
			if not tags then
				return false
			end
			for _, tag in ipairs(tags) do
				if tag == "melee" then
					return true
				end
			end
			return false
		end,
		apply = function(_ctx: SkillQueryTypes.SkillQueryContext, result: SkillQueryTypes.SkillQueryResult)
			local baseAmount = result.values.amount
			if typeof(baseAmount) ~= "number" then
				return
			end
			result.values.resource = StatTypes.PoolStats.Health
			result.values.amount = baseAmount * 1.5
		end,
	}

	skillModifierRegistry.register(playerId, "resolveSkillCost", meleeDoubleCost)

	task.delay(5, function()
		statsManager.setBaseStat(playerId, StatTypes.StaticStats.AttackSpeed, 1)
		statsManager.addModifier(
			playerId,
			StatTypes.StaticStats.HealthRegeneration,
			PercentOfStatModifier.new({
				value = 0.2, -- 20% of max health
				source_id = "health_regen_test",
				targetStat = StatTypes.PoolStats.Health,
				description = "Base health regeneration",
			})
		)

		print("Starting in 5s...")
		attributesManager.addToAttribute(player, AttributeTypes.Attributes.Perception, 1)

		task.delay(5, function()
			attributesManager.applyAllScaling(player)
		end)
	end)

	task.delay(1.0, function()
		local entityId = registrar.getEntityId(character)
		if entityId then
			testModifiers.runTests(entityId)
		end
	end)
end

function Dev.onPlayerRemoving(player: Player)
	local Testing = require(script.Parent.Parent.Testing.Testing)
	Testing.stopTests(player)
end

return Dev
