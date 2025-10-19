--!strict
-- Server-side configuration for player stat system
-- Defines all available stats and their properties (kept server-only)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Stat = require(ReplicatedStorage.Shared.StatClass)
local PoolStat = require(ReplicatedStorage.Shared.PoolStatClass)
local Types = require(ReplicatedStorage.Shared.StatTypes)

local StatsConfig = {}

-- Default pool configurations (using enum-like constants)
StatsConfig.DEFAULT_POOLS = {
	[Types.PoolStats.Health] = { baseValue = 100, minValue = 0, maxValue = 9999, name = "Health" },
	[Types.PoolStats.Mana] = { baseValue = 50, minValue = 0, maxValue = 9999, name = "Mana" },
	[Types.PoolStats.Stamina] = { baseValue = 100, minValue = 0, maxValue = 9999, name = "Stamina" },
	[Types.PoolStats.ManaShield] = { baseValue = 0, minValue = 0, maxValue = 9999, name = "Mana Shield" },
}

-- Default stat configurations (using enum-like constants)
StatsConfig.DEFAULT_STATS = {
	[Types.StaticStats.PhysicalDamage] = { baseValue = 10, minValue = 0, maxValue = 9999, name = "Physical Damage" },
	[Types.StaticStats.MagicDamage] = { baseValue = 0, minValue = 0, maxValue = 9999, name = "Magic Damage" },
	[Types.StaticStats.CriticalHitChance] = {
		baseValue = 5,
		minValue = 0,
		maxValue = 100,
		name = "Critical Hit Chance",
	}, -- percentage
	[Types.StaticStats.CriticalHitDamage] = {
		baseValue = 150,
		minValue = 100,
		maxValue = 1000,
		name = "Critical Hit Damage",
	}, -- percentage
	[Types.StaticStats.HealthRegeneration] = {
		baseValue = 1,
		minValue = 0,
		maxValue = 999999,
		name = "Health Regeneration",
	}, -- per second
	[Types.StaticStats.ManaRegeneration] = {
		baseValue = 0,
		minValue = 0,
		maxValue = 999999,
		name = "Mana Regeneration",
	}, -- per second
	[Types.StaticStats.StaminaRegeneration] = {
		baseValue = 5,
		minValue = 0,
		maxValue = 999999,
		name = "Stamina Regeneration",
	}, -- per second
	[Types.StaticStats.PerceptionDistance] = {
		baseValue = 60,
		minValue = 0,
		maxValue = 2000,
		name = "Perception Distance",
	},
	[Types.StaticStats.PerceptionTier] = {
		baseValue = 0,
		minValue = 0,
		maxValue = 10,
		name = "Perception Tier",
	},
}

-- Helper function to create a new set of stats using Stat and PoolStat classes
function StatsConfig.createDefaultStats(): Types.PlayerStats
	local stats = {} :: any

	-- Create pools using enum constants
	for poolName, config in pairs(StatsConfig.DEFAULT_POOLS) do
		stats[poolName] = PoolStat.new(config)
	end

	-- Create stats using enum constants
	for statName, config in pairs(StatsConfig.DEFAULT_STATS) do
		stats[statName] = Stat.new(config)
	end

	return stats :: Types.PlayerStats
end

-- Validate a stat value against limits
function StatsConfig.validateStatValue(value: number): number
	return math.clamp(value, 0, 99999)
end

return StatsConfig
