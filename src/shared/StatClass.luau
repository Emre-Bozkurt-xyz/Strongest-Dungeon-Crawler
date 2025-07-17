-- Example of how a class-based stat system could look

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
		statType = "static", -- Identify this as a static stat
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

function Stat:updateModifier(source_id: string, newValue: number): boolean
	for _, modifier in ipairs(self.modifiers) do
		if modifier.source_id == source_id then
			modifier:modifyValue(newValue)
			self:_markDirty()
			return true
		end
	end
	warn(`Modifier '{source_id}' not found in {self.name}`)
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

	-- Start with base value
	local finalValue = self.baseValue

	-- Apply modifiers using their apply method
	for _, modifier in ipairs(self.modifiers) do
		if modifier.apply then
			finalValue = modifier:apply(finalValue, allStats)
		else
			warn(`Modifier from {modifier.source_id} does not have an apply method`)
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
			-- Calculate the actual contribution of this modifier
			local baseValue = self.baseValue
			local modifiedValue = modifier:apply(baseValue, nil)
			local contribution = modifiedValue - baseValue

			table.insert(breakdown, {
				name = modifier.description or modifier.source_id,
				value = contribution,
				type = modifier.type or "unknown",
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

-- Force cache invalidation (useful when external systems modify this stat)
function Stat:invalidateCache()
	self:_markDirty()
end

return Stat
