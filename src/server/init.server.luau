-- Main server initialization script
print("Server starting...")

-- Initialize the stats management system
local StatsManager = require(script.Stats.StatsManager)
local AttributesManager = require(script.Stats.AttributesManager)

-- Initialize the regeneration service
local RegenerationService = require(script.Services.RegenerationService)
RegenerationService.start()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SkillsManager = require(script.SkillsFramework.SkillsManager)
local AttributeTypes = require(ReplicatedStorage.Shared.AttributeTypes)
local PercentOfStatModifier = require(ReplicatedStorage.Shared.Modifiers.PercentOfStatModifier)
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)
local NPCSpawner = require(script.NPCService.NPCSpawner)
local ComponentManager = require(script.NPCService.ComponentManager)
local NPCManager = require(script.NPCService.NPCManager)
local EntityInfoService = require(script.Services.EntityInfoService)
local ChannelRegistry = require(ReplicatedStorage.Shared.Networking.ChannelRegistry)
local ChannelDefinitions = require(ReplicatedStorage.Shared.Networking.Channels)
local StatsMediator = require(script.Stats.StatsMediator)

ChannelRegistry.load(ChannelDefinitions)

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
	NPCSpawner.spawn("Dummy", {
		position = Vector3.new(90, 5, 0),
		debug = true,
	})

	-- NPCSpawner.spawn("Dummy", {
	-- 	position = Vector3.new(95, 5, 0),
	-- 	debug = true
	-- })

	-- NPCSpawner.spawn("Dummy", {
	-- 	position = Vector3.new(90, 5, 20),
	-- 	debug = true
	-- })

	SkillsManager.addSkill(player, "Punch")
	SkillsManager.addSkill(player, "TripleStrike")
	SkillsManager.addSkill(player, "Dash")
	SkillsManager.addSkill(player, "ManaBall")

	StatsManager.addModifier(
		player,
		StatTypes.StaticStats.ManaRegeneration,
		PercentOfStatModifier.new({
			value = 0.1, -- 10% of max mana
			source_id = "mana_regen_test",
			targetStat = StatTypes.PoolStats.Mana,
			description = "Base mana regeneration",
		})
	)

	wait(5)

	-- StatsMediator.observe("resolveSkillCost", function(ctx)
	-- 	print("Observing skill cost resolution for", ctx.entity.Name)
	-- 	local meta = ctx.options and ctx.options.metadata
	-- 	if not meta then return end

	-- 	if meta.skillTags and typeof(meta.skillTags) == "table" and table.find(meta.skillTags, "melee")  then
	-- 		local cost = meta.adjustedCost or meta.baseCost or ctx.compute()
	-- 		meta.adjustedCost = math.max(0, cost * 1.5)
	-- 		meta.overrideStat = StatTypes.PoolStats.Health
	-- 		local options = ctx.options
	-- 		if options then
	-- 			options.overrideStat = StatTypes.PoolStats.Health
	-- 		end
	-- 	end
	-- 	return nil
	-- end)

	StatsManager.setBaseStat(player, StatTypes.StaticStats.AttackSpeed, 1)
	StatsManager.addModifier(
		player,
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

	-- StatsManager.setProfilingEnabled(true)
	-- AttributesManager.setProfilingEnabled(true)

	-- require(script.Testing.TestStatsProfiler).run({ iterations = 50000 })

	-- StatsManager.setProfilingEnabled(false)
	-- AttributesManager.setProfilingEnabled(false)

	-- Testing.runAllTests(player)
	-- Testing.testCombatLogCoverage(player)
	-- Testing.testModifierOperations(player)

	-- small scale testing

	-- print(`🧪 Server: Testing attribute operations for {player.Name}`)

	-- -- Test adding intelligence
	-- AttributesManager.addToAttribute(player, AttributeTypes.Attributes.Intelligence, 5)
	-- print(`Added 5 Intelligence to {player.Name}`)

	-- -- Debug available points
	-- local availablePoints = AttributesManager.getAvailableAttributePoints(player)
	-- print(`{player.Name} has {availablePoints} available attribute points`)

	-- StatsManager.removeFromPool(player, StatTypes.PoolStats.Mana, 30)
	-- StatsManager.removeFromPool(player, StatTypes.PoolStats.Health, 30)
	-- StatsManager.removeFromPool(player, StatTypes.PoolStats.Stamina, 30)

	-- wait(2)

	-- -- Test spending an attribute point
	-- AttributesManager.spendAttributePoint(player, AttributeTypes.Attributes.Intelligence)
	-- print(`{player.Name} spent 1 attribute point on Intelligence`)

	-- AttributesManager.addToAttribute(player, AttributeTypes.Attributes.Perception, 20)

	-- wait(2)

	-- -- Add intelligence modifier
	-- AttributesManager.addModifier(player, AttributeTypes.Attributes.Intelligence, {
	-- 	value = 3, -- +3 Intelligence
	-- 	source_id = "intelligence_modifier_test",
	-- 	description = "Test Intelligence Modifier",
	-- })
end

-- Connect to new players for demo purposes
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(_character)
		--_removeBundles(_character)
	end)
	spawn(function()
		setupPlayerCommands(player)
	end)
end)

-- Clean up tests when player leaves
Players.PlayerRemoving:Connect(function(player)
	Testing.stopTests(player)
end)

print("Server initialized with Examples")

-- Initialize NPC system and drive component updates each frame
NPCManager.initialize()
RunService.Heartbeat:Connect(function(dt)
	ComponentManager.updateAll(dt)
end)

-- Start presence-only entity info streaming (Phase 2 scaffold)
EntityInfoService.start()
