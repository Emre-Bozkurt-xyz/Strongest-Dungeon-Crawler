--!strict
-- The game's stat defaults: every stat, pool and resource an entity has, with its base value and
-- limits (kept server-only).
--
-- Base stats are derived from this file every time an entity registers (StatsManager.register: a
-- player at session start, an NPC when it spawns) and are never saved, so a value changed here
-- reaches every player at their next session. Anything a player keeps must be saved as its inputs
-- (level, attribute points, items), never as a stat value: a saved stat would freeze the number this
-- file gave it and hide every later change.
--
-- Above these defaults, an entity's definition (an NPC spec's configure step) may set its own, and
-- dev tooling or tests lay overrides on top (StatClass). Dev tooling can also lay session-only values
-- over this file's (dev/GameDefaults); nothing persists them, so this file stays the one place a
-- default is kept. Outside Studio nothing can set them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Stat = require(ReplicatedStorage.Shared.StatClass)
local PoolStat = require(ReplicatedStorage.Shared.PoolStatClass)
local ResourceStat = require(ReplicatedStorage.Shared.ResourceStatClass)
local Types = require(ReplicatedStorage.Shared.StatTypes)
local DebugConfig = require(ReplicatedStorage.Shared.Debug.DebugConfig)

local StatsConfig = {}

export type StatKind = "pool" | "static" | "resource"

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
	[Types.StaticStats.MagicDamage] = { baseValue = 10, minValue = 0, maxValue = 9999, name = "Magic Damage" },
	[Types.StaticStats.AttackSpeed] = {
		baseValue = 1.0,
		minValue = 0.1,
		maxValue = 10.0,
		name = "Attack Speed",
	}, -- multiplier
	[Types.StaticStats.SpellCastSpeed] = {
		baseValue = 1.0,
		minValue = 0.1,
		maxValue = 10.0,
		name = "Spell Cast Speed",
	}, -- multiplier
	[Types.StaticStats.Armor] = {
		baseValue = 0,
		minValue = 0,
		maxValue = 9999,
		name = "Armor",
	},
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
		baseValue = 15,
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
	-- Percentage points. Resistance can go negative (a debuff); what it may reach is capped where
	-- damage is taken (CombatService), not here, so the cap can rise from classes and gear.
	[Types.StaticStats.FireResistance] = { baseValue = 0, minValue = -100, maxValue = 100, name = "Fire Resistance" },
	[Types.StaticStats.FrostResistance] = { baseValue = 0, minValue = -100, maxValue = 100, name = "Frost Resistance" },
	[Types.StaticStats.FirePenetration] = { baseValue = 0, minValue = 0, maxValue = 100, name = "Fire Penetration" },
	[Types.StaticStats.FrostPenetration] = { baseValue = 0, minValue = 0, maxValue = 100, name = "Frost Penetration" },
}

StatsConfig.DEFAULT_RESOURCES = {
	[Types.ResourceStats.Energy] = {
		baseValue = 100,
		minValue = 0,
		maxValue = 100,
		name = "Energy",
		description = "Skill resource",
		regenerationRate = 15,
		depletionThreshold = 0,
	},
}

local KIND_TABLES: { { kind: StatKind, configs: { [string]: any } } } = {
	{ kind = "pool", configs = StatsConfig.DEFAULT_POOLS },
	{ kind = "static", configs = StatsConfig.DEFAULT_STATS },
	{ kind = "resource", configs = StatsConfig.DEFAULT_RESOURCES },
}

-- Base values dev tooling has laid over this file's for the session, by stat name.
local sessionDefaults: { [string]: number } = {}

local function configOf(statName: string): (any?, StatKind?)
	for _, entry in ipairs(KIND_TABLES) do
		local config = entry.configs[statName]
		if config then
			return config, entry.kind
		end
	end
	return nil, nil
end

-- The config a new stat is built from: this file's, with the session's base value when one is set.
local function effectiveConfig(statName: string, config: any): any
	local session = sessionDefaults[statName]
	if session == nil then
		return config
	end
	local copy = table.clone(config)
	copy.baseValue = session
	return copy
end

-- Helper function to create a new set of stats using Stat and PoolStat classes
function StatsConfig.createDefaultStats(): Types.EntityStats
	local stats = {} :: any

	-- Create pools using enum constants
	for poolName, config in pairs(StatsConfig.DEFAULT_POOLS) do
		stats[poolName] = PoolStat.new(effectiveConfig(poolName, config))
	end

	-- Create stats using enum constants
	for statName, config in pairs(StatsConfig.DEFAULT_STATS) do
		stats[statName] = Stat.new(effectiveConfig(statName, config))
	end

	for resourceName, config in pairs(StatsConfig.DEFAULT_RESOURCES) do
		stats[resourceName] = ResourceStat.new(effectiveConfig(resourceName, config))
	end

	return stats :: Types.EntityStats
end

-- Every stat, pool and resource name in this file, sorted.
function StatsConfig.names(): { string }
	local names: { string } = {}
	for _, entry in ipairs(KIND_TABLES) do
		for name in pairs(entry.configs) do
			table.insert(names, name)
		end
	end
	table.sort(names)
	return names
end

function StatsConfig.kindOf(statName: string): StatKind?
	local _, kind = configOf(statName)
	return kind
end

-- The stat's limits, which also bound any base value set on it.
function StatsConfig.limitsOf(statName: string): (number, number)
	local config = configOf(statName)
	if not config then
		return -math.huge, math.huge
	end
	return config.minValue or 0, config.maxValue or math.huge
end

-- The base value written in this file.
function StatsConfig.fileDefault(statName: string): number?
	local config = configOf(statName)
	return if config then config.baseValue else nil
end

-- The base value a new entity gets: the session's when dev tooling set one, else the file's.
function StatsConfig.defaultOf(statName: string): number?
	local session = sessionDefaults[statName]
	if session ~= nil then
		return session
	end
	return StatsConfig.fileDefault(statName)
end

-- Lays a session-only base value over the file's (nil removes it). Refused outside Studio, so a live
-- server can only ever build stats from the file.
function StatsConfig.setSessionDefault(statName: string, value: number?): boolean
	if not DebugConfig.isDev() or configOf(statName) == nil then
		return false
	end
	sessionDefaults[statName] = value
	return true
end

-- The session values, by stat name.
function StatsConfig.sessionDefaults(): { [string]: number }
	return table.clone(sessionDefaults)
end

return StatsConfig
