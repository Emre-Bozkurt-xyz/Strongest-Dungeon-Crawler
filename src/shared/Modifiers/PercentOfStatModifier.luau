-- Example of how a class-based modifier system could look

local StatModifier = require(game.ReplicatedStorage.Shared.Modifiers.StatModifier)
local Types = require(game.ReplicatedStorage.Shared.StatTypes)

type StatType = Types.StatType

local PercentOfStatModifier = {}
PercentOfStatModifier.__index = PercentOfStatModifier
setmetatable(PercentOfStatModifier, { __index = StatModifier })

export type PercentOfModifierConfig = {
	value: number,
	condition: ((stats: any) -> boolean)?,
	description: string,
	source_id: string,
	targetStat: StatType, -- The stat this modifier is a percentage of
}

-- Create a new modifier
function PercentOfStatModifier.new(config: PercentOfModifierConfig)
	local self = StatModifier.new({
		value = config.value,
		type = "percent",
		condition = config.condition,
		description = config.description,
		source_id = config.source_id,
	})
	setmetatable(self, PercentOfStatModifier)

	self.targetStat = config.targetStat
	self.modifierType = "PercentOfStatModifier" -- Identify modifier type for serialization

	return self
end

-- Calculate the modifier value dynamically
function PercentOfStatModifier:apply(lastValue: number, allStats: any): number
	if not self.isActive then
		return lastValue
	end

	-- Check condition if it exists
	if self.condition and not self.condition(allStats) then
		return lastValue
	end

	-- Get the target stat value
	if allStats and allStats[self.targetStat] then
		local targetStat = allStats[self.targetStat]
		-- Check if it's a stat object with getValue method or a simple table
		if type(targetStat) == "table" and targetStat.getValue then
			return lastValue + (targetStat:getValue(allStats) * self.value)
		end
	end

	return lastValue
end

return PercentOfStatModifier
