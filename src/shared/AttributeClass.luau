--!strict
-- Attribute class - handles individual attributes with modifiers and scaling effects

local Attribute = {}
Attribute.__index = Attribute

export type AttributeConfig = {
	baseValue: number,
	minValue: number?,
	maxValue: number?,
	name: string,
	description: string?,
}

export type AttributeModifier = {
	value: number,
	source_id: string,
	description: string?,
}

function Attribute.new(config: AttributeConfig)
	local self = setmetatable({
		name = config.name,
		baseValue = config.baseValue,
		minValue = config.minValue or 0,
		maxValue = config.maxValue or 999,
		description = config.description,
		modifiers = {} :: { AttributeModifier },
		_cachedValue = nil,
		_isDirty = true,
	}, Attribute)

	return self
end

-- Add a modifier to this attribute
function Attribute:addModifier(modifier: AttributeModifier)
	table.insert(self.modifiers, modifier)
	self:_markDirty()
end

-- Remove a modifier by source_id
function Attribute:removeModifier(source_id: string): boolean
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
function Attribute:getModifiersFromSource(source_id: string): { AttributeModifier }
	local result = {}
	for _, modifier in ipairs(self.modifiers) do
		if modifier.source_id == source_id then
			table.insert(result, modifier)
		end
	end
	return result
end

-- Calculate the final value with all modifiers (attributes only use flat bonuses)
function Attribute:getValue(): number
	if not self._isDirty and self._cachedValue then
		return self._cachedValue
	end

	-- Start with base value
	local finalValue: number = self:getBaseValue() :: number + self:getModifierTotal() :: number

	-- Clamp to min/max
	finalValue = math.clamp(finalValue, self.minValue, self.maxValue)

	-- Cache the result
	self._cachedValue = finalValue
	self._isDirty = false

	return finalValue
end

-- Get base value without modifiers
function Attribute:getBaseValue(): number
	return self.baseValue
end

-- Set base value
function Attribute:setBaseValue(value: number)
	self.baseValue = math.clamp(value, self.minValue, self.maxValue)
	self:_markDirty()
end

-- Add to base value
function Attribute:addToBaseValue(amount: number)
	local currentBase: number = self.baseValue
	local newValue: number = currentBase + amount
	self.baseValue = math.clamp(newValue, self.minValue, self.maxValue)
	self:_markDirty()
end

-- Get modifier breakdown for debugging/UI
function Attribute:getModifierBreakdown(): { { name: string, value: number, source: string } }
	local breakdown = {}

	for _, modifier in ipairs(self.modifiers) do
		table.insert(breakdown, {
			name = modifier.description or modifier.source_id,
			value = modifier.value,
			source = modifier.source_id,
		})
	end

	return breakdown
end

-- Get total modifier bonus
function Attribute:getModifierTotal(): number
	local total = 0
	for _, modifier in ipairs(self.modifiers) do
		total += modifier.value
	end
	return total
end

-- ATTRIBUTE SCALING FUNCTIONS
-- These will be used to scale stats based on attribute values

-- Calculate damage scaling from Strength
function Attribute:getPhysicalDamageScaling(): number
	local attributeValue: number = self:getValue()
	-- Every point of Strength gives +2 Physical Damage
	return attributeValue * 2
end

-- Calculate mana scaling from Intelligence
function Attribute:getManaScaling(): number
	local attributeValue: number = self:getValue()
	-- Every point of Intelligence gives +5 Mana
	return attributeValue * 5
end

-- Calculate magic damage scaling from Intelligence
function Attribute:getMagicDamageScaling(): number
	local attributeValue: number = self:getValue()
	-- Every point of Intelligence gives +1.5 Magic Damage
	return attributeValue * 1.5
end

-- Calculate stamina scaling from Dexterity
function Attribute:getStaminaScaling(): number
	local attributeValue: number = self:getValue()
	-- Every point of Dexterity gives +3 Stamina
	return attributeValue * 3
end

-- Calculate critical hit chance scaling from Dexterity
function Attribute:getCriticalHitChanceScaling(): number
	local attributeValue: number = self:getValue()
	-- Every point of Dexterity gives +0.2% Crit Chance
	return attributeValue * 0.2
end

-- Calculate health scaling from Strength (secondary effect)
function Attribute:getHealthScaling(): number
	local attributeValue: number = self:getValue()
	-- Every point of Strength gives +3 Health
	return attributeValue * 3
end

-- Calculate defense scaling from Defense attribute
function Attribute:getDefenseScaling(): number
	local attributeValue: number = self:getValue()
	-- Defense doesn't scale stats directly, but could scale damage reduction
	-- For now, return the raw value for other systems to use
	return attributeValue
end

-- Calculate perception scaling effects
function Attribute:getPerceptionScaling(): number
	local attributeValue: number = self:getValue()
	-- Perception could scale accuracy, detection range, etc.
	-- For now, return the raw value for other systems to use
	return attributeValue
end

-- Mark the cached value as dirty
function Attribute:_markDirty()
	self._isDirty = true
end

return Attribute
