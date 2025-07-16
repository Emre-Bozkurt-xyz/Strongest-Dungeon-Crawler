--!strict
-- Utility functions for working with stat types
-- Uses the centralized type system from StatTypes.luau

local Types = require(script.Parent.StatTypes)
local Stat = require(script.Parent.StatClass)
local PoolStat = require(script.Parent.PoolStatClass)

local StatTypeUtil = {}

-- ========================================
-- TYPE CHECKING FUNCTIONS
-- ========================================

-- Method 1: Check using statType property (recommended)
function StatTypeUtil.isPoolStat(stat): boolean
	return stat.statType == Types.StatClassTypes.Pool
end

function StatTypeUtil.isStaticStat(stat): boolean
	return stat.statType == Types.StatClassTypes.Static
end

-- Method 2: Check using stat name against PoolType enum
function StatTypeUtil.isPoolName(statName: string): boolean
	for _, poolName in pairs(Types.AllPoolStatNames) do
		if statName == poolName then
			return true
		end
	end
	return false
end

function StatTypeUtil.isStaticStatName(statName: string): boolean
	for _, staticStatName in pairs(Types.AllStaticStatNames) do
		if statName == staticStatName then
			return true
		end
	end
	return false
end

-- Method 3: Duck typing - check for pool-specific methods
function StatTypeUtil.hasPoolMethods(stat): boolean
	return stat.getCurrentValue ~= nil and stat.addReservation ~= nil
end

-- Helper function to get the appropriate value from any stat
function StatTypeUtil.getStatValue(stat, allStats): number
	if StatTypeUtil.isPoolStat(stat) then
		return stat:getCurrentValue()
	else
		return stat:getValue(allStats)
	end
end

-- Helper function to get the max value from any stat
function StatTypeUtil.getMaxValue(stat, allStats): number
	if StatTypeUtil.isPoolStat(stat) then
		return stat:getMaxValue(allStats)
	else
		return stat:getValue(allStats)
	end
end

-- =========================================
-- COMPREHENSIVE SERIALIZATION FUNCTIONS
-- =========================================

function StatTypeUtil.serializeStats(stats: Types.PlayerStats)
	local serialized = {} :: any

	-- Serialize all stats (both pools and static) with FULL state
	for statName, stat in pairs(stats) do
		if StatTypeUtil.isPoolStat(stat) then
			-- Pool stat - capture ALL state including reservations and modifiers
			serialized[statName] = {
				-- Class identification
				statType = "pool",

				-- Basic properties
				name = stat.name,
				description = stat.description,
				baseValue = stat:getBaseValue(),
				minValue = stat.minValue,
				maxValue = stat.maxValue,

				-- Pool-specific properties
				currentValue = stat:getCurrentValue(),
				reservations = stat.reservations or {},

				-- Modifiers (full state)
				modifiers = StatTypeUtil._serializeModifiers(stat.modifiers or {}),

				-- Cache state (for performance)
				_cachedValue = stat._cachedValue,
				_cachedMaxValue = stat._cachedMaxValue,
				_isDirty = stat._isDirty or true,
				_maxIsDirty = stat._maxIsDirty or true,
			}
		else
			-- Static stat - capture ALL state including modifiers
			serialized[statName] = {
				-- Class identification
				statType = "static",

				-- Basic properties
				name = stat.name,
				description = stat.description,
				baseValue = stat:getBaseValue(),
				minValue = stat.minValue,
				maxValue = stat.maxValue,

				-- Modifiers (full state)
				modifiers = StatTypeUtil._serializeModifiers(stat.modifiers or {}),

				-- Cache state (for performance)
				_cachedValue = stat._cachedValue,
				_isDirty = stat._isDirty or true,
			}
		end
	end

	return serialized
end

-- Helper function to serialize modifiers with their full state
function StatTypeUtil._serializeModifiers(modifiers: { any })
	local serializedModifiers = {}

	for _, modifier in ipairs(modifiers) do
		local modifierData = {
			-- Core modifier properties
			value = modifier.value,
			type = modifier.type,
			source_id = modifier.source_id,
			description = modifier.description,
			isActive = modifier.isActive,

			-- Store the modifier class type for reconstruction
			modifierType = modifier.modifierType or "StatModifier",
		}

		-- Add special properties for PercentOfStatModifier
		if modifier.modifierType == "PercentOfStatModifier" then
			modifierData.targetStat = modifier.targetStat
		end

		table.insert(serializedModifiers, modifierData)
	end

	return serializedModifiers
end

function StatTypeUtil.deserializeStats(serialized: any): Types.PlayerStats
	local stats = {} :: any

	-- Import modifier classes for reconstruction
	local StatModifier = require(game.ReplicatedStorage.Shared.Modifiers.StatModifier)
	local PercentOfStatModifier = require(game.ReplicatedStorage.Shared.Modifiers.PercentOfStatModifier)

	-- First pass: Create all stat instances with basic properties
	for statName, data in pairs(serialized) do
		if data.statType == "pool" then
			-- Create PoolStat instance
			local poolStat = PoolStat.new({
				name = data.name,
				baseValue = data.baseValue,
				minValue = data.minValue,
				maxValue = data.maxValue,
				description = data.description,
				startAtMax = false, -- We'll set current value manually
			})

			-- Restore pool-specific state
			poolStat:setCurrentValue(data.currentValue)
			poolStat.reservations = data.reservations or {}

			-- Restore cache state
			poolStat._cachedValue = data._cachedValue
			poolStat._cachedMaxValue = data._cachedMaxValue
			poolStat._isDirty = data._isDirty
			poolStat._maxIsDirty = data._maxIsDirty

			stats[statName] = poolStat
		else
			-- Create StaticStat instance
			local staticStat = Stat.new({
				name = data.name,
				baseValue = data.baseValue,
				minValue = data.minValue,
				maxValue = data.maxValue,
				description = data.description,
			})

			-- Restore cache state
			staticStat._cachedValue = data._cachedValue
			staticStat._isDirty = data._isDirty

			stats[statName] = staticStat
		end
	end

	-- Second pass: Restore all modifiers (after all stats exist for cross-references)
	for statName, data in pairs(serialized) do
		local stat = stats[statName]

		-- Clear the default empty modifiers array
		stat.modifiers = {}

		-- Restore each modifier
		for _, modifierData in ipairs(data.modifiers or {}) do
			local modifier

			-- Reconstruct the appropriate modifier type
			if modifierData.modifierType == "PercentOfStatModifier" then
				modifier = PercentOfStatModifier.new({
					value = modifierData.value,
					condition = nil, -- Functions can't be serialized, will need special handling if needed
					description = modifierData.description or "",
					source_id = modifierData.source_id,
					targetStat = modifierData.targetStat,
				})
			else
				-- Default to StatModifier
				modifier = StatModifier.new({
					value = modifierData.value,
					type = modifierData.type,
					source_id = modifierData.source_id,
				})
			end

			-- Restore modifier state
			modifier.description = modifierData.description
			modifier.isActive = modifierData.isActive

			-- Add to stat
			table.insert(stat.modifiers, modifier)
		end
	end

	return stats :: Types.PlayerStats
end

-- Usage examples:
--[[
local playerStat = StatsManager.getStat(player, "Health")

if StatTypeUtil.isPoolStat(playerStat) then
	print("This is a pool stat")
	print("Current:", playerStat:getCurrentValue())
	print("Max:", playerStat:getMaxValue())
else
	print("This is a static stat")
	print("Value:", playerStat:getValue())
end

-- Or using stat name
if StatTypeUtil.isPoolName("Health") then
	print("Health is a pool type")
end
]]

return StatTypeUtil
