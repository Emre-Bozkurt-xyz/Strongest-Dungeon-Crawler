--!strict
-- Server dev-only hooks: the dev command system, scenarios, and the per-player baseline that makes
-- a real save playable in a dev session.
--
-- The world (NPCs, shrine, stages) belongs to scenarios (dev/Scenarios) and is set up once per
-- server; what is set up here is per player.
--
-- Debug flags keep their DebugConfig defaults (off) so the output stays readable; a session turns
-- one on with `flag <name> true`, and a scenario with its `flags` field.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PercentOfStatModifier = require(ReplicatedStorage.Shared.Modifiers.PercentOfStatModifier)
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)
local AnimationDrafts = require(script.Parent.AnimationDrafts)
local StarterKit = require(script.Parent.StarterKit)

local Dev = {}

function Dev.start(_ctx)
	AnimationDrafts.start()
	require(script.Parent.Characters).start()
	require(script.Parent.Commands).start()
	require(script.Parent.Scenarios).start()
end

-- Once per player session (not per respawn). Skills and regeneration are session state and are set
-- up every time; the starter items and attribute point are saved, so only a new save gets them.
-- Then the player joins the scenario world (the first one boots it).
function Dev.onSessionStart(player: Player, _character: Model, grantStarterKit: boolean)
	local registrar = require(script.Parent.Parent.Services.Registrar)
	local statsManager = require(script.Parent.Parent.Stats.StatsManager)
	local attributesManager = require(script.Parent.Parent.Stats.AttributesManager)
	local skillsManager = require(script.Parent.Parent.SkillsFramework.SkillsManager)
	local inventoryService = require(script.Parent.Parent.Inventory.InventoryService)

	local playerId = registrar.getPlayerId(player)
	if not playerId then
		warn("Dev.onSessionStart: No playerId for player", player.Name)
		return
	end

	for _, skillName in ipairs(StarterKit.skills) do
		skillsManager.addSkill(playerId, skillName)
	end

	if grantStarterKit then
		for _, item in ipairs(StarterKit.items) do
			local entry = item :: any
			local meta = if entry.rarity then { rarity = entry.rarity } else nil
			inventoryService.addItem(playerId, entry[1], entry[2] or 1, meta)
		end
		for attribute, amount in pairs(StarterKit.attributes) do
			attributesManager.addToAttribute(player, attribute :: any, amount)
		end
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
	attributesManager.applyAllScaling(player)

	require(script.Parent.Scenarios).onPlayerReady(player)
end

function Dev.onPlayerRemoving(player: Player)
	local Testing = require(script.Parent.Parent.Testing.Testing)
	Testing.stopTests(player)
end

return Dev
