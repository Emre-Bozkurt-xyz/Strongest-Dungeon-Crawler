--!strict
-- Server dev-only hooks (testing, debug, demo setup).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local DebugConfig = require(ReplicatedStorage.Shared.Debug.DebugConfig)
local AttributeTypes = require(ReplicatedStorage.Shared.AttributeTypes)
local PercentOfStatModifier = require(ReplicatedStorage.Shared.Modifiers.PercentOfStatModifier)
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)
local SkillQueryTypes = require(ReplicatedStorage.Shared.skills.SkillQueryTypes)

local Dev = {}

function Dev.start(ctx)
	DebugConfig.setMany({
		sessionPerf = false,
		skills = true,
		session = true,
		projectiles = true,
	})
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

	skillsManager.addSkill(playerId, "Punch")
	skillsManager.addSkill(playerId, "TripleStrike")
	skillsManager.addSkill(playerId, "Dash")
	skillsManager.addSkill(playerId, "DodgeRoll")
	skillsManager.addSkill(playerId, "ManaBall")
	skillsManager.addSkill(playerId, "CascadingManaBalls")

	inventoryService.addItem(playerId, "mana_potion", 5)
	inventoryService.addItem(playerId, "iron_sword", 1, { rarity = "normal" })
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
