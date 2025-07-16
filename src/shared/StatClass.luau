-- Example of how a class-based stat system could look

local StatModifier = require(game.ReplicatedStorage.Shared.Modifiers.StatModifier)

local Stat = {}
Stat.__index = Stat

export type StatConfig = {
	baseValue: number,
	minValue: number?,
	maxValue: number?,
	name: string,
	description: string?,
}

function Stat.new(config: StatConfig)
	local self = setmetatable({
		name = config.name,
		baseValue = config.baseValue,
		minValue = config.minValue or 0,
		maxValue = config.maxValue or math.huge,
		description = config.description,
		modifiers = {},
		_cachedValue = nil,
		_isDirty = true,
	}, Stat)

	return self
end

-- Add a modifier to this stat
function Stat:addModifier(modifier)
	table.insert(self.modifiers, modifier)
	self:_markDirty()
end

-- Remove a modifier by source_id
function Stat:removeModifier(source_id: string): boolean
	for i, modifier in ipairs(self.modifiers) do
		if modifier.source_id == source_id then
			table.remove(self.modifiers, i)
			self:_markDirty()
			return true
		end
	end
	return false
end

-- Get all modifiers from a specific source
function Stat:getModifiersFromSource(source_id: string)
	local result = {}
	for _, modifier in ipairs(self.modifiers) do
		if modifier.source_id == source_id then
			table.insert(result, modifier)
		end
	end
	return result
end

-- Calculate the final value with all modifiers
function Stat:getValue(allStats: any?): number
	if not self._isDirty and self._cachedValue then
		return self._cachedValue
	end

	-- Sort modifiers by priority (higher priority applied last)
	local sortedModifiers = {}
	for _, modifier in ipairs(self.modifiers) do
		table.insert(sortedModifiers, modifier)
	end
	table.sort(sortedModifiers, function(a, b)
		return (a.priority or 0) < (b.priority or 0)
	end)

	-- Start with base value
	local finalValue = self.baseValue

	-- Apply flat modifiers first
	for _, modifier in ipairs(sortedModifiers) do
		local modValue = modifier:calculateValue(finalValue, allStats)
		if modifier.value then -- Flat modifier
			finalValue = finalValue + modValue
		end
	end

	-- Then apply percentage modifiers
	for _, modifier in ipairs(sortedModifiers) do
		if modifier.percentage then -- Percentage modifier
			local modValue = modifier:calculateValue(finalValue, allStats)
			finalValue = finalValue + modValue
		end
	end

	-- Clamp to min/max
	finalValue = math.clamp(finalValue, self.minValue, self.maxValue)

	-- Cache the result
	self._cachedValue = finalValue
	self._isDirty = false

	return finalValue
end

-- Get base value without modifiers
function Stat:getBaseValue(): number
	return self.baseValue
end

-- Set base value
function Stat:setBaseValue(value: number)
	self.baseValue = value
	self:_markDirty()
end

-- Add to base value
function Stat:addToBaseValue(amount: number)
	self.baseValue = self.baseValue + amount
	self:_markDirty()
end

-- Get modifier breakdown for debugging/UI
function Stat:getModifierBreakdown(): { { name: string, value: number, type: string, source: string } }
	local breakdown = {}

	for _, modifier in ipairs(self.modifiers) do
		if modifier.isActive then
			table.insert(breakdown, {
				name = modifier.description,
				value = modifier:calculateValue(self.baseValue, nil),
				type = modifier.value and "flat" or "percentage",
				source = modifier.source_id,
			})
		end
	end

	return breakdown
end

-- Mark the cached value as dirty
function Stat:_markDirty()
	self._isDirty = true
end

-- Examples of usage:

--[[
-- Create a health stat
local health = Stat.new({
	baseValue = 100,
	minValue = 0,
	maxValue = 9999,
	name = "Health",
	description = "Player's life force"
})

-- Add modifiers
local constitution = StatModifier.new({
	sourceStatType = "Constitution",
	percentage = 10,
	description = "Constitution bonus (+10% per CON)",
	source_id = "constitution_bonus"
})

local helmet = StatModifier.new({
	value = 25,
	description = "Iron Helmet (+25 HP)",
	source_id = "iron_helmet"
})

health:addModifier(constitution)
health:addModifier(helmet)

-- Get final value
local finalHealth = health:getValue(allPlayerStats)

-- Remove equipment
health:removeModifier("iron_helmet")
--]]

return Stat
