--!strict
-- SINGLE SOURCE OF TRUTH for all stat system types
-- This is your equivalent of a C# namespace with all your enums and types

--[[
TYPE ARCHITECTURE OVERVIEW:

1. STAT NAMES (String Literals) - The actual names used in code
   - StaticStatType: "PhysicalDamage", "MagicDamage", etc.
   - PoolType: "Health", "Mana", etc.
   - StatType: Union of above two

2. STAT OBJECTS (Class Instances) - The actual stat class instances
   - StatClass: For static stats like damage, crit chance
   - PoolStatClass: For pool stats like health, mana
   - PlayerStats: Collection holding all stat instances

3. CONFIGURATION TYPES - For creating new stats
   - StatConfig: Config for creating StatClass
   - PoolConfig: Config for creating PoolStatClass

4. MODIFIER TYPES - For stat modifications
   - ModifierConfig: Config for creating modifiers
   - PoolReservation: Config for pool reservations
]]

-- Import the class types
local Stat = require(script.Parent.StatClass)
local PoolStat = require(script.Parent.PoolStatClass)
local ResourceStat = require(script.Parent.ResourceStatClass)

local Types = {}

-- ========================================
-- STRING LITERAL TYPES (Your "Enums")
-- ========================================

-- Static stat names (calculated values like damage, crit)
export type StaticStatType =
	"PhysicalDamage"
	| "MagicDamage"
	| "AttackSpeed"
	| "SpellCastSpeed"
	| "CriticalHitChance"
	| "CriticalHitDamage"
	| "HealthRegeneration"
	| "ManaRegeneration"
	| "StaminaRegeneration"
	| "PerceptionDistance"
	| "PerceptionTier"

-- Pool stat names (current/max values like health, mana)
export type PoolType = "Health" | "Mana" | "Stamina" | "ManaShield"

-- Resource stat names (hybrid pools with regeneration + callbacks)
export type ResourceStatType = "Energy"

-- All stat names combined
export type StatType = StaticStatType | PoolType | ResourceStatType

-- ========================================
-- CLASS INSTANCE TYPES
-- ========================================

-- The actual collection of all player stats (both static and pool)
export type PlayerStats = {
	-- Pool-based stats (have current/max values and reservations)
	Health: typeof(PoolStat.new({ baseValue = 0, name = "" })),
	Mana: typeof(PoolStat.new({ baseValue = 0, name = "" })),
	Stamina: typeof(PoolStat.new({ baseValue = 0, name = "" })),
	ManaShield: typeof(PoolStat.new({ baseValue = 0, name = "" })),
	-- Resource stats
	Energy: typeof(ResourceStat.new({ baseValue = 0, name = "" })),

	-- Static stats (calculated values only)
	PhysicalDamage: typeof(Stat.new({ baseValue = 0, name = "" })),
	MagicDamage: typeof(Stat.new({ baseValue = 0, name = "" })),
	AttackSpeed: typeof(Stat.new({ baseValue = 0, name = "" })),
	SpellCastSpeed: typeof(Stat.new({ baseValue = 0, name = "" })),
	CriticalHitChance: typeof(Stat.new({ baseValue = 0, name = "" })),
	CriticalHitDamage: typeof(Stat.new({ baseValue = 0, name = "" })),
	HealthRegeneration: typeof(Stat.new({ baseValue = 0, name = "" })),
	ManaRegeneration: typeof(Stat.new({ baseValue = 0, name = "" })),
	StaminaRegeneration: typeof(Stat.new({ baseValue = 0, name = "" })),
	PerceptionDistance: typeof(Stat.new({ baseValue = 0, name = "" })),
	PerceptionTier: typeof(Stat.new({ baseValue = 0, name = "" })),
}

export type EntityStats = {
	[string]: typeof(Stat.new({ baseValue = 0, name = "" }))
		| typeof(PoolStat.new({ baseValue = 0, name = "" }))
		| typeof(ResourceStat.new({ baseValue = 0, name = "" })),
}

export type StaticStatInstance = typeof(Stat.new({ baseValue = 0, name = "" }))
export type PoolStatInstance = typeof(PoolStat.new({ baseValue = 0, name = "" }))
export type ResourceStatInstance = typeof(ResourceStat.new({ baseValue = 0, name = "" }))
export type StatInstance = StaticStatInstance | PoolStatInstance | ResourceStatInstance

-- ========================================
-- CONFIGURATION TYPES (for creating stats)
-- ========================================

-- Re-export important types from other modules
export type StatConfig = {
	baseValue: number,
	minValue: number?,
	maxValue: number?,
	name: string,
	description: string?,
}

export type PoolConfig = {
	baseValue: number,
	minValue: number?,
	maxValue: number?,
	name: string,
	description: string?,
	startAtMax: boolean?,
}

export type ModifierConfig = {
	value: number?,
	type: "flat" | "percent"?,
	condition: ((stats: any, context: any?) -> boolean)?,
	source_id: string,
	description: string?,
	strategy: any?,
	strategyKind: string?,
	strategyParams: { [string]: any }?,
	payload: { [string]: any }?,
	tags: { string }?,
	stackGroup: string?,
	priority: number?,
	metadata: { [string]: any }?,
	duration: number?,
	expiresAt: number?,
}

export type PoolReservation = {
	amount: number,
	type: "flat" | "percent",
	source_id: string,
	description: string,
}

-- ========================================
-- ENUM-LIKE CONSTANTS (Like C# static classes)
-- ========================================

-- Static stat names (like C# enum)
Types.StaticStats = {
	PhysicalDamage = "PhysicalDamage" :: StaticStatType,
	MagicDamage = "MagicDamage" :: StaticStatType,
	AttackSpeed = "AttackSpeed" :: StaticStatType,
	SpellCastSpeed = "SpellCastSpeed" :: StaticStatType,
	CriticalHitChance = "CriticalHitChance" :: StaticStatType,
	CriticalHitDamage = "CriticalHitDamage" :: StaticStatType,
	HealthRegeneration = "HealthRegeneration" :: StaticStatType,
	ManaRegeneration = "ManaRegeneration" :: StaticStatType,
	StaminaRegeneration = "StaminaRegeneration" :: StaticStatType,
	PerceptionDistance = "PerceptionDistance" :: StaticStatType,
	PerceptionTier = "PerceptionTier" :: StaticStatType,
}

-- Pool stat names (like C# enum)
Types.PoolStats = {
	Health = "Health" :: PoolType,
	Mana = "Mana" :: PoolType,
	Stamina = "Stamina" :: PoolType,
	ManaShield = "ManaShield" :: PoolType,
}

Types.ResourceStats = {
	Energy = "Energy" :: ResourceStatType,
}

-- Modifier types
Types.ModifierTypes = {
	Flat = "flat",
	Percent = "percent",
}

-- Stat class types (for type checking)
Types.StatClassTypes = {
	Static = "static",
	Pool = "pool",
	Resource = "resource",
}

-- ========================================
-- UTILITY ARRAYS (for iteration)
-- ========================================

Types.AllStaticStatNames = {
	"PhysicalDamage",
	"MagicDamage",
	"CriticalHitChance",
	"CriticalHitDamage",
	"HealthRegeneration",
	"ManaRegeneration",
	"StaminaRegeneration",
	"PerceptionDistance",
	"PerceptionTier",
} :: { StaticStatType }

Types.AllPoolStatNames = {
	"Health",
	"Mana",
	"Stamina",
	"ManaShield",
} :: { PoolType }

Types.AllResourceStatNames = {
	"Energy",
} :: { ResourceStatType }

Types.AllStatNames = {
	-- Pool stats
	"Health",
	"Mana",
	"Stamina",
	"ManaShield",
	-- Resource stats
	"Energy",
	-- Static stats
	"PhysicalDamage",
	"MagicDamage",
	"CriticalHitChance",
	"CriticalHitDamage",
	"HealthRegeneration",
	"ManaRegeneration",
	"StaminaRegeneration",
	"PerceptionDistance",
	"PerceptionTier",
} :: { StatType }

return Types
