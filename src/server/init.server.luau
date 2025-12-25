-- Main server initialization script
print("Server starting...")

-- Service imports
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

-- Registrar for new players
local Registrar = require(script.Services.Registrar)

-- Initialize the stats management system
local StatsManager = require(script.Stats.StatsManager)
local AttributesManager = require(script.Stats.AttributesManager)

-- Initialize the regeneration service
local RegenerationService = require(script.Services.RegenerationService)
RegenerationService.start()

local SessionManager = require(script.SkillsFramework.SessionManager)
local SkillsManager = require(script.SkillsFramework.SkillsManager)
local SkillMetadataService = require(script.SkillsFramework.SkillMetadataService)
local AttributeTypes = require(ReplicatedStorage.Shared.AttributeTypes)
local PercentOfStatModifier = require(ReplicatedStorage.Shared.Modifiers.PercentOfStatModifier)
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)
local NPCSpawner = require(script.NPCService.NPCSpawner)
local ComponentManager = require(script.NPCService.ComponentManager)
local NPCManager = require(script.NPCService.NPCManager)
local EntityInfoService = require(script.Services.EntityInfoService)
local SkillModifierRegistry = require(script.Stats.SkillModifierRegistry)
local StaggerSystem = require(script.Services.StaggerSystem)
local SkillQueryTypes = require(ReplicatedStorage.Shared.skills.SkillQueryTypes)
local TestModifiers = require(script.SkillsFramework.TestModifiers)

local ENABLE_SESSION_PERF_TIMER = false
local SESSION_PERF_INTERVAL = 15

-- Initialize StatusEffectsService context for attack composition
local StatusEffectsService = require(script.StatusEffects.StatusEffectsService)
local CombatService = require(script.Services.CombatService)

-- Networking singleton already created at top with all channels loaded
-- No manual _ensureChannel() calls needed anymore

StatusEffectsService.setContext({
	applyAttack = function(targetEntityId: string, attack: any, sourceEntityId: string)
		CombatService.applyAttack(targetEntityId, attack, sourceEntityId)
	end,
})

if ENABLE_SESSION_PERF_TIMER then
	task.spawn(function()
		SessionManager.resetPerfStats()
		while true do
			task.wait(SESSION_PERF_INTERVAL)
			local stats = SessionManager.getPerfStats()
			print(`[SessionPerf] Server {HttpService:JSONEncode(stats)}`)
			SessionManager.resetPerfStats()
		end
	end)
end

local Testing = require(script.Testing.Testing)

local function _removeBundles(_character)
	local humanoid = _character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		error("Character has no humanoid.")
	end

	wait(1)

	local descriptionClone = humanoid:GetAppliedDescription()
	descriptionClone.Head = 0
	descriptionClone.LeftArm = 0
	descriptionClone.RightArm = 0
	descriptionClone.LeftLeg = 0
	descriptionClone.RightLeg = 0
	descriptionClone.Torso = 0
	humanoid:ApplyDescription(descriptionClone)
end

-- Example function to test the system
local function setupPlayerCommands(player: Player)
	local playerId = Registrar.getPlayerId(player)

	NPCSpawner.spawn("Dummy", {
		position = Vector3.new(90, 5, 0),
	})

	-- NPCSpawner.spawn("Dummy", {
	-- 	position = Vector3.new(95, 5, 0),
	-- 	debug = true
	-- })

	-- NPCSpawner.spawn("Dummy", {
	-- 	position = Vector3.new(90, 5, 20),
	-- 	debug = true
	-- })

	SkillsManager.addSkill(playerId, "Punch")
	SkillsManager.addSkill(playerId, "TripleStrike")
	SkillsManager.addSkill(playerId, "Dash")
	-- ManaBall disabled - projectile system needs rework
	-- SkillsManager.addSkill(playerId, "ManaBall")

	StatsManager.addModifier(
		playerId,
		StatTypes.StaticStats.ManaRegeneration,
		PercentOfStatModifier.new({
			value = 0.1, -- 10% of max mana
			source_id = "mana_regen_test",
			targetStat = StatTypes.PoolStats.Mana,
			description = "Base mana regeneration",
		})
	)

	local meleeDoubleCost: SkillModifierRegistry.SkillModifier = {
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

			-- Convert to health and scale by 1.5x
			result.values.resource = StatTypes.PoolStats.Health
			result.values.amount = baseAmount * 1.5
		end,
	}

	SkillModifierRegistry.register(playerId, "resolveSkillCost", meleeDoubleCost)

	wait(5)

	StatsManager.setBaseStat(playerId, StatTypes.StaticStats.AttackSpeed, 1)
	StatsManager.addModifier(
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
	AttributesManager.addToAttribute(player, AttributeTypes.Attributes.Perception, 1)

	wait(5)

	-- Apply attribute scaling after stats and attributes are initialized
	AttributesManager.applyAllScaling(player)
end

-- Connect to new players for demo purposes
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		Registrar.registerEntity(character, true)
		task.defer(function()
			StatsManager.initializePlayerStats(player)
			setupPlayerCommands(player)

			-- Send initial skill metadata after stats are initialized
			-- Small delay to ensure all stats/modifiers are applied
			task.delay(0.5, function()
				SkillMetadataService.updateAllSkills(player)
			end)

			-- Run modifier tests after player is fully initialized
			task.delay(1.0, function()
				local entityId = Registrar.getEntityId(character)
				if entityId then
					TestModifiers.runTests(entityId)
				end
			end)
		end)
	end)
end)

-- Clean up tests when player leaves
Players.PlayerRemoving:Connect(function(player)
	Testing.stopTests(player)
	StatsManager.cleanupPlayerStats(player)
	Registrar.unregisterPlayer(player)
end)

print("Server initialized with Examples")

-- Initialize NPC system and drive component updates each frame
NPCManager.initialize()
RunService.Heartbeat:Connect(function(dt)
	ComponentManager.updateAll(dt)
end)

-- Start presence-only entity info streaming (Phase 2 scaffold)
EntityInfoService.start()

-- Initialize stagger system
StaggerSystem.init()

-- Phase 0: Start SessionManager heartbeat (module already required at top)
SessionManager.startHeartbeat()
