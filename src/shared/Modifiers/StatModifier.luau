--!strict
-- Example of how a class-based modifier system could look

local StatModifier = {}
StatModifier.__index = StatModifier

export type ModifierConfig = {
	value: number,
	type: "flat" | "percent",
	condition: ((stats: any) -> boolean)?,
	source_id: string,
}

-- Create a new modifier
function StatModifier.new(config: ModifierConfig)
	local self = setmetatable({
		value = config.value,
		type = config.type,
		condition = config.condition,
		description = "",
		source_id = config.source_id,
		isActive = true,
		modifierType = "StatModifier", -- Identify modifier type for serialization
	}, StatModifier)

	return self
end

-- Calculate the modifier value dynamically
function StatModifier:apply(lastValue: number, allStats: any): number
	local returnValue = lastValue

	if not self.isActive then
		return returnValue
	end

	-- Check condition if it exists
	if self.condition and not self.condition(allStats) then
		return returnValue
	end

	-- Fixed value modifier
	if self.value and self.type == "flat" then
		returnValue += self.value
	-- Percentage modifier
	elseif self.value and self.type == "percent" then
		returnValue += returnValue * self.value
	end

	return returnValue
end

-- Modify the value
function StatModifier:modifyValue(newValue: number)
	self.value = newValue
end

-- Enable/disable the modifier
function StatModifier:setActive(active: boolean)
	self.isActive = active
end

return StatModifier
