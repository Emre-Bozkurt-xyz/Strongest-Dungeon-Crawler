-- Example of how a class-based modifier system could look

local StatModifier = require(game.ReplicatedStorage.Shared.Modifiers.StatModifier)
local ModifierFactories = require(game.ReplicatedStorage.Shared.Modifiers.Factories)
local Strategies = require(game.ReplicatedStorage.Shared.Modifiers.Strategies)
local Types = require(game.ReplicatedStorage.Shared.StatTypes)

type StatType = Types.StatType

local PercentOfStatModifier = {}
PercentOfStatModifier.__index = PercentOfStatModifier
setmetatable(PercentOfStatModifier, { __index = StatModifier })

export type PercentOfModifierConfig = {
	value: number,
	condition: ((stats: any, context: Strategies.StrategyContext?) -> boolean)?,
	description: string,
	source_id: string,
	targetStat: StatType, -- The stat this modifier is a percentage of
	tags: { string }?,
	stackGroup: string?,
	priority: number?,
	metadata: { [string]: any }?,
	payload: { [string]: any }?,
	duration: number?,
	expiresAt: number?,
}

-- Create a new modifier
function PercentOfStatModifier.new(config: PercentOfModifierConfig)
	local payload = table.clone(config.payload or {})
	payload.targetStat = config.targetStat

	local modifier = ModifierFactories.percentOfStat({
		sourceId = config.source_id,
	   	description = config.description,
	   	condition = config.condition,
	   	tags = config.tags,
	   	stackGroup = config.stackGroup,
	   	priority = config.priority,
	   	metadata = config.metadata,
	   	percent = config.value,
	   	payload = payload,
	   	targetStat = config.targetStat,
		duration = config.duration,
		expiresAt = config.expiresAt,
	})
	setmetatable(modifier, PercentOfStatModifier)

	local modifierRecord = modifier :: any
	modifierRecord.targetStat = config.targetStat

	return modifier
end

-- Calculate the modifier value dynamically
function PercentOfStatModifier:apply(context)
	return StatModifier.apply(self, context)
end

return PercentOfStatModifier
