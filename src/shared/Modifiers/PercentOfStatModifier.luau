-- Example of how a class-based modifier system could look

local StatModifier = require(game.ReplicatedStorage.Shared.Modifiers.StatModifier)

local StatsConfig = require(game.ReplicatedStorage.Shared.StatsConfig)
local AttributesConfig = require(game.ReplicatedStorage.Shared.AttributesConfig)

type StatType = StatsConfig.StatType
type AttributeType = AttributesConfig.AttributeType

local PercentOfStatModifier = {}
PercentOfStatModifier.__index = PercentOfStatModifier
setmetatable(PercentOfStatModifier, { __index = StatModifier })

export type PercentOfModifierConfig = {
	value: number,
	condition: ((stats: any) -> boolean)?,
	description: string,
	source_id: string,
	targetStat: StatType | AttributeType, -- The stat this modifier is a percentage of
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

	return self
end

-- Calculate the modifier value dynamically
function PercentOfStatModifier:calculateValue(allStats: any): number
	if not self.isActive then
		return 0
	end

	-- Check condition if it exists
	if self.condition and not self.condition(allStats) then
		return 0
	end

	-- Get the target stat value
	local targetStatValue = 0
	if allStats and allStats[self.targetStat] then
		local targetStat = allStats[self.targetStat]
		-- Check if it's a stat object with getValue method or a simple table
		if type(targetStat) == "table" and targetStat.getValue then
			targetStatValue = targetStat:getValue(allStats)
		elseif type(targetStat) == "table" and targetStat.base then
			targetStatValue = targetStat.base
		elseif type(targetStat) == "number" then
			targetStatValue = targetStat
		end
	end

	-- Calculate percentage of the target stat
	return targetStatValue * self.value
end

return PercentOfStatModifier
