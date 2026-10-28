-- Sunder: armor broken open for a while (Armor Break). Lowers the target's Armor by a share
-- (`armorReduction`, default 25%) through an ordinary stat modifier, removed when it ends. Refreshes
-- rather than stacks: a second blow keeps the armor open, it does not open it further.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ModifierFactories = require(ReplicatedStorage.Shared.Modifiers.Factories)
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)
local StatsManager = require(ServerScriptService.Server.Stats.StatsManager)

local SOURCE = "status::Sunder"
local DEFAULT_REDUCTION = 0.25

return {
	id = "Sunder",
	isHarmful = true,
	duration = 4,
	maxStacks = 1,
	stacking = "aggregate",
	durationPolicy = "refresh",
	defaultParams = { armorReduction = DEFAULT_REDUCTION },
	potencyKeys = { "armorReduction" },
	onApply = function(target: string, _source: string?, params: any?, _stacks: number)
		local reduction = (params and params.armorReduction) or DEFAULT_REDUCTION
		StatsManager.removeModifier(target, StatTypes.StaticStats.Armor, SOURCE)
		StatsManager.addModifier(
			target,
			StatTypes.StaticStats.Armor,
			ModifierFactories.percentBuff({ sourceId = SOURCE, percent = -reduction, description = "Sundered" })
		)
	end,
	onRemove = function(target: string, _source: string?, _stacks: number)
		StatsManager.removeModifier(target, StatTypes.StaticStats.Armor, SOURCE)
	end,
}
