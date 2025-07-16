--!strict
-- Shared configuration for player attributes system
-- This file defines all available attributes and their properties

export type AttributeType = "Strength" | "Defense" | "Dexterity" | "Intelligence" | "Perception"

export type AttributeModifier = {
	value: number, -- The value of the modifier
	source_id: string, -- Description of the source
}

export type AttributeData = {
	base: number,
	modifiers: { AttributeModifier }, -- List of active modifiers affecting this attribute
}

export type PlayerAttributes = {
	[AttributeType]: AttributeData,
}

local AttributesConfig = {}

-- Default attribute configuration
AttributesConfig.DEFAULT_ATTRIBUTES = {
	Strength = { base = 0 },
	Defense = { base = 0 },
	Dexterity = { base = 0 },
	Intelligence = { base = 0 },
	Perception = { base = 0 },
}

-- Attribute limits
AttributesConfig.MIN_ATTRIBUTE_VALUE = 0
AttributesConfig.MAX_ATTRIBUTE_VALUE = 999

-- Attribute descriptions for UI
AttributesConfig.ATTRIBUTE_DESCRIPTIONS = {
	Strength = "Increases physical damage",
	Defense = "Increases damage resistance and armor rating",
	Dexterity = "Increases attack speed and critical hit chance",
	Intelligence = "Increases mana pool and spell effectiveness",
	Perception = "Increases accuracy and detection abilities",
}

-- Helper function to create a deep copy of default attributes
function AttributesConfig.createDefaultAttributes(): PlayerAttributes
	local attributes: PlayerAttributes = {}
	for attributeName, attributeData in pairs(AttributesConfig.DEFAULT_ATTRIBUTES) do
		attributes[attributeName] = {
			base = attributeData.base,
			modifiers = {},
		}
	end
	return attributes
end

-- Calculate current attribute value (base + bonus)
function AttributesConfig.getAdditiveModifiers(attributeData: AttributeData): number
	local total = 0

	for _, modifier in ipairs(attributeData.modifiers) do
		total += modifier.value
	end

	return total
end

-- Validate attribute value is within bounds
function AttributesConfig.validateAttributeValue(value: number): number
	return math.clamp(value, AttributesConfig.MIN_ATTRIBUTE_VALUE, AttributesConfig.MAX_ATTRIBUTE_VALUE)
end

return AttributesConfig
