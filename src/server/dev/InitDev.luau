--!strict
-- Server dev-only hooks (testing, debug, demo setup).

local CollectionService = game:GetService("CollectionService")
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

-- A stand-in Attunement Shrine for the dev map: a slab, a pillar and a floating crystal, tagged so
-- AttunementService gives it a prompt. Real shrines are placed in maps with the same tag.
local function buildPlaceholderShrine(at: Vector3)
	local Attunement = require(ReplicatedStorage.Shared.progression.Attunement)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { game:GetService("Players"):GetChildren() }
	local hit = workspace:Raycast(at + Vector3.new(0, 100, 0), Vector3.new(0, -400, 0), params)
	local ground = if hit then hit.Position.Y else at.Y

	local model = Instance.new("Model")
	model.Name = "AttunementShrine"
	local function part(name: string, size: Vector3, y: number, props: { [string]: any }): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Anchored = true
		p.CFrame = CFrame.new(at.X, ground + y, at.Z)
		for key, value in pairs(props) do
			(p :: any)[key] = value
		end
		p.Parent = model
		return p
	end
	local stone = Color3.fromRGB(70, 72, 82)
	local base = part("Base", Vector3.new(7, 0.8, 7), 0.4, { Material = Enum.Material.Slate, Color = stone })
	part("Pillar", Vector3.new(1.6, 3.4, 1.6), 0.8 + 1.7, { Material = Enum.Material.Slate, Color = stone })
	local crystal = part("Crystal", Vector3.new(1, 1.8, 1), 6, {
		Material = Enum.Material.Neon,
		Color = Color3.fromRGB(120, 200, 255),
		CanCollide = false,
		CastShadow = false,
	})
	crystal.CFrame *= CFrame.Angles(0, math.rad(45), math.rad(45))
	local light = Instance.new("PointLight")
	light.Color = crystal.Color
	light.Range = 12
	light.Brightness = 1.5
	light.Parent = crystal
	model.PrimaryPart = base
	model.Parent = workspace
	CollectionService:AddTag(model, Attunement.SHRINE_TAG)
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

	-- Sets a branch's XP outright, so unlocks and the mastery canvas can be exercised without earning
	-- them: ServerStorage.DevSetMastery:Fire(player, "Blunt", "trunk", 120).
	local devSetMastery = Instance.new("BindableEvent")
	devSetMastery.Name = "DevSetMastery"
	devSetMastery.Parent = game:GetService("ServerStorage")
	devSetMastery.Event:Connect(function(player: Player, track: string, branch: string, xp: number)
		local masteryService = require(script.Parent.Parent.Progression.MasteryService)
		masteryService.setBranchXp(player, track, branch, xp)
	end)

	-- Lands a plain physical hit from the player on the nearest NPC named `npcName`, through the real
	-- combat path, so kills and what follows them (contribution, character XP, death, respawn) can be
	-- exercised without walking up to it: ServerStorage.DevHit:Fire(player, "Slime", 50).
	local devHit = Instance.new("BindableEvent")
	devHit.Name = "DevHit"
	devHit.Parent = game:GetService("ServerStorage")
	devHit.Event:Connect(function(player: Player, npcName: string, amount: number)
		local registrar = require(script.Parent.Parent.Services.Registrar)
		local combatService = require(script.Parent.Parent.Services.CombatService)
		local playerId = registrar.getPlayerId(player)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not playerId or not root then
			return
		end
		local nearest, nearestDistance = nil, math.huge
		for _, entity in ipairs(registrar.getAllEntities()) do
			local entityRoot = entity:FindFirstChild("HumanoidRootPart") :: BasePart?
			local position = if entityRoot then entityRoot.Position else entity:GetPivot().Position
			local distance = (position - root.Position).Magnitude
			if entity.Name == npcName and entity:GetAttribute("Dead") ~= true and distance < nearestDistance then
				nearest, nearestDistance = entity, distance
			end
		end
		local targetId = nearest and registrar.getEntityId(nearest)
		if not targetId then
			warn("[DevHit] No living NPC named", npcName)
			return
		end
		combatService.applyAttack(targetId, {
			packets = { { type = "damage", damageType = "Physical", amount = amount } },
			sourceId = playerId,
			metadata = { skillId = "DevHit" },
		}, playerId)
	end)

	-- Adds character XP outright: ServerStorage.DevGrantXP:Fire(player, 500).
	local devGrantXp = Instance.new("BindableEvent")
	devGrantXp.Name = "DevGrantXP"
	devGrantXp.Parent = game:GetService("ServerStorage")
	devGrantXp.Event:Connect(function(player: Player, amount: number)
		require(script.Parent.Parent.Progression.CharacterService).grant(player, amount)
	end)

	buildPlaceholderShrine(Vector3.new(80, 0, -14))

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

-- Once per player session (not per respawn). Skills, test modifiers and NPCs are session state and
-- are set up every time; the starter items and attribute point are saved, so only a new save gets
-- them.
function Dev.onSessionStart(player: Player, character: Model, grantStarterKit: boolean)
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
		warn("Dev.onSessionStart: No playerId for player", player.Name)
		return
	end

	npcSpawner.spawn("Dummy", {
		position = Vector3.new(90, 5, 0),
	})
	npcSpawner.spawn("Slime", {
		position = Vector3.new(100, 5, 0),
		respawnDelay = 10,
	})

	-- Phase B: BasicAttack replaces Punch as the bound offensive primitive (D6, adaptive per
	-- current weapon). Punch stays granted only implicitly via NPCs/tests; players get BasicAttack.
	skillsManager.addSkill(playerId, "BasicAttack")
	skillsManager.addSkill(playerId, "TripleStrike")
	skillsManager.addSkill(playerId, "Dash")
	skillsManager.addSkill(playerId, "DodgeRoll")
	skillsManager.addSkill(playerId, "ManaBall")
	skillsManager.addSkill(playerId, "CascadingManaBalls")

	if grantStarterKit then
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
	end

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
		if grantStarterKit then
			attributesManager.addToAttribute(player, AttributeTypes.Attributes.Perception, 1)
		end

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
