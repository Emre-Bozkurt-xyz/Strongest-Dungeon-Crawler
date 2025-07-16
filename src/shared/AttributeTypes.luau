--!strict
-- SINGLE SOURCE OF TRUTH for all attribute system types
-- This is your equivalent of a C# namespace with all your attribute enums and types

--[[
ATTRIBUTE TYPE ARCHITECTURE OVERVIEW:

1. ATTRIBUTE NAMES (String Literals) - The actual names used in code
   - AttributeType: "Strength", "Intelligence", etc.

2. ATTRIBUTE OBJECTS (Class Instances) - The actual attribute class instances
   - AttributeClass: For individual attributes with modifiers and scaling
   - PlayerAttributes: Collection holding all attribute instances

3. CONFIGURATION TYPES - For creating new attributes
   - AttributeConfig: Config for creating AttributeClass
   - AttributeModifier: Config for attribute modifiers

4. SCALING RELATIONSHIPS - How attributes affect stats
   - Strength → Physical Damage, Health
   - Intelligence → Magic Damage, Mana
   - Dexterity → Stamina, Critical Hit Chance
   - Defense → Damage Reduction
   - Perception → Accuracy, Detection
]]

-- Import the class type
local Attribute = require(game.ReplicatedStorage.Shared.AttributeClass)

local AttributeTypes = {}

-- ========================================
-- STRING LITERAL TYPES (Your "Enums")
-- ========================================

-- All available attribute names
export type AttributeType = "Strength" | "Defense" | "Dexterity" | "Intelligence" | "Perception"

-- ========================================
-- CLASS INSTANCE TYPES
-- ========================================

-- The actual collection of all player attributes
export type PlayerAttributes = {
	Strength: typeof(Attribute.new({ baseValue = 0, name = "" })),
	Defense: typeof(Attribute.new({ baseValue = 0, name = "" })),
	Dexterity: typeof(Attribute.new({ baseValue = 0, name = "" })),
	Intelligence: typeof(Attribute.new({ baseValue = 0, name = "" })),
	Perception: typeof(Attribute.new({ baseValue = 0, name = "" })),
}

-- ========================================
-- CONFIGURATION TYPES (for creating attributes)
-- ========================================

-- Re-export important types from AttributeClass
export type AttributeConfig = Attribute.AttributeConfig

export type AttributeModifier = Attribute.AttributeModifier

-- ========================================
-- ENUM-LIKE CONSTANTS (Like C# static classes)
-- ========================================

-- Attribute names (like C# enum)
AttributeTypes.Attributes = {
	Strength = "Strength" :: AttributeType,
	Defense = "Defense" :: AttributeType,
	Dexterity = "Dexterity" :: AttributeType,
	Intelligence = "Intelligence" :: AttributeType,
	Perception = "Perception" :: AttributeType,
}

-- ========================================
-- UTILITY ARRAYS (for iteration)
-- ========================================

AttributeTypes.AllAttributeNames = {
	"Strength",
	"Defense",
	"Dexterity",
	"Intelligence",
	"Perception",
} :: { AttributeType }

-- ========================================
-- ATTRIBUTE DESCRIPTIONS
-- ========================================

AttributeTypes.Descriptions = {
	Strength = "Increases physical damage and health",
	Defense = "Increases damage resistance and armor rating",
	Dexterity = "Increases critical hit chance and stamina",
	Intelligence = "Increases magic damage and mana pool",
	Perception = "Increases accuracy and detection abilities",
}

return AttributeTypes
