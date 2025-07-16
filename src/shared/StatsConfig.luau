--!strict
-- Shared configuration for player stat system
-- This file defines all available stats and their properties

export type StatType =
	"Health"
	| "Mana"
	| "Stamina"
	| "Mana Shield"
	| "Physical Damage"
	| "Magic Damage"
	| "Critical Hit Chance"
	| "Critical Hit Damage"
	| "Health Regeneration"
	| "Mana Regeneration"
	| "Stamina Regeneration"

export type StatModifier = {
	value: number, -- The value of the modifier
	type: "flat" | "percent", -- The type of the modifier
	of: StatType, -- WIP: Adds a flat value to the stat based on another stat
	source_id: string, -- Description of the source
}

export type StatData = {
	base: number, -- Base value of the stat
	modifiers: { StatModifier },
}

export type PlayerStats = {
	[StatType]: StatData,
}

local StatsConfig = {}

-- Default stat configuration
StatsConfig.DEFAULT_STATS = {
	Health = { base = 100 },
	Mana = { base = 50 },
	Stamina = { base = 100 },
	ManaShield = { base = 0 },
	PhysicalDamage = { base = 10 },
	MagicDamage = { base = 0 },
	CriticalHitChance = { base = 5 }, -- in percentage
	CriticalHitDamage = { base = 150 }, -- in percentage
	HealthRegeneration = { base = 1 }, -- per second
	ManaRegeneration = { base = 1 }, -- per second
	StaminaRegeneration = { base = 1 }, -- per second
}

StatsConfig.DEFAULT_MODIFIERS = {
	{ value = 0.02, type = "percent", of = "Mana", source_id = "base_mana_regen" },
	{ value = 0.01, type = "percent", of = "Stamina", source_id = "base_stamina_regen" },
	{ value = 0.05, type = "flat", of = "Health", source_id = "base_health_regen" },
	{ value = 0.1, type = "flat", of = "ManaShield", source_id = "base_mana_shield" },
	{ value = 0.1, type = "flat", of = "PhysicalDamage", source_id = "base_physical_damage" },
}

-- Stat limits
StatsConfig.MIN_STAT_VALUE = 0
StatsConfig.MAX_STAT_VALUE = 99999

-- Helper function to create a deep copy of default stats
function StatsConfig.createDefaultStats(): PlayerStats
	local stats: PlayerStats = {}
	for statName, statData in pairs(StatsConfig.DEFAULT_STATS) do
		stats[statName] = {
			base = statData.base,
			modifiers = {},
		}
	end
	return stats
end

-- Validate a stat value against limits
function StatsConfig.validateStatValue(value: number): number
	return math.clamp(value, StatsConfig.MIN_STAT_VALUE, StatsConfig.MAX_STAT_VALUE)
end

return StatsConfig
