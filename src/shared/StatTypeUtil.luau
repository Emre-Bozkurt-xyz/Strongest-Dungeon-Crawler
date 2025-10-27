--!strict
-- Utility functions for working with stat types
-- Uses the centralized type system from StatTypes.luau

local Types = require(script.Parent.StatTypes)
local Stat = require(script.Parent.StatClass)
local PoolStat = require(script.Parent.PoolStatClass)
local ResourceStat = require(script.Parent.ResourceStatClass)
local ModifierFactories = require(script.Parent.Modifiers.Factories)

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

function StatTypeUtil.isResourceStat(stat): boolean
	return stat.statType == Types.StatClassTypes.Resource
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

function StatTypeUtil.isResourceName(statName: string): boolean
	for _, resourceName in pairs(Types.AllResourceStatNames) do
		if statName == resourceName then
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
	if StatTypeUtil.isPoolStat(stat) or StatTypeUtil.isResourceStat(stat) then
		return stat:getCurrentValue()
	else
		return stat:getValue(allStats)
	end
end

-- Helper function to get the max value from any stat
function StatTypeUtil.getMaxValue(stat, allStats): number
	if StatTypeUtil.isPoolStat(stat) or StatTypeUtil.isResourceStat(stat) then
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
		if StatTypeUtil.isResourceStat(stat) then
			-- Resource stat - hybrid pool with metadata
			serialized[statName] = {
				statType = "resource",
				name = stat.name,
				description = stat.description,
				baseValue = stat:getBaseValue(),
				minValue = stat.minValue,
				maxValue = stat.maxValue,
				currentValue = stat:getCurrentValue(),
				reservations = stat.reservations or {},
				metadata = stat:getMetadataSnapshot(),
				modifiers = StatTypeUtil._serializeModifiers(stat.modifiers or {}),
				_cachedValue = stat._cachedValue,
				_cachedMaxValue = stat._maxCachedValue,
				_isDirty = stat._isDirty or true,
				_maxIsDirty = stat._maxIsDirty or true,
			}
		elseif StatTypeUtil.isPoolStat(stat) then
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
		local payloadCopy = modifier.payload and table.clone(modifier.payload) or nil
		local strategyParamsCopy = modifier.strategyParams and table.clone(modifier.strategyParams) or nil
		local tagsCopy = modifier.tags and table.clone(modifier.tags) or nil
		local metadataCopy = modifier.metadata and table.clone(modifier.metadata) or nil

		local modifierData = {
			-- Core modifier properties
			value = modifier.value,
			type = modifier.type,
			source_id = modifier.source_id,
			description = modifier.description,
			isActive = modifier.isActive,
			strategyKind = modifier.strategyKind,
			payload = payloadCopy,
			strategyParams = strategyParamsCopy,
			tags = tagsCopy,
			stackGroup = modifier.stackGroup,
			priority = modifier.priority,
			duration = modifier.duration,
			expiresAt = modifier.expiresAt,
			metadata = metadataCopy,

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

	-- Store current values for pool/resource stats to restore AFTER modifiers
	local pendingCurrentValues = {} :: { [string]: { value: number, statType: string } }

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

			-- Store current value for later restoration (after modifiers are added)
			pendingCurrentValues[statName] = { value = data.currentValue, statType = "pool" }
			poolStat.reservations = data.reservations or {}

			-- DON'T restore cache state - let it recalculate fresh on client
			-- poolStat._cachedValue = data._cachedValue
			-- poolStat._cachedMaxValue = data._cachedMaxValue
			-- poolStat._isDirty = data._isDirty
			-- poolStat._maxIsDirty = data._maxIsDirty

			stats[statName] = poolStat
		elseif data.statType == "resource" then
			local metadata = data.metadata or {}
			local resourceStat = ResourceStat.new({
				name = data.name,
				baseValue = data.baseValue,
				minValue = data.minValue,
				maxValue = data.maxValue,
				description = data.description,
				startAtMax = false,
				regenerationRate = metadata.regenerationRate,
				regenPaused = metadata.regenerationPaused,
				depletionThreshold = metadata.depletionThreshold,
			})

			resourceStat:applyMetadataSnapshot(metadata)
			resourceStat.reservations = data.reservations or {}
			pendingCurrentValues[statName] = { value = data.currentValue, statType = "resource" }

			stats[statName] = resourceStat
		else
			-- Create StaticStat instance
			local staticStat = Stat.new({
				name = data.name,
				baseValue = data.baseValue,
				minValue = data.minValue,
				maxValue = data.maxValue,
				description = data.description,
			})

			-- DON'T restore cache state - let it recalculate fresh on client
			-- staticStat._cachedValue = data._cachedValue
			-- staticStat._isDirty = data._isDirty

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
			local modifier = ModifierFactories.hydrate(modifierData)
			if modifier then
				modifier.description = modifierData.description
				modifier.isActive = modifierData.isActive
				table.insert(stat.modifiers, modifier)
			end
		end
	end

	-- Third pass: Restore current values for pool/resource stats (now that modifiers are in place)
	for statName, payload in pairs(pendingCurrentValues) do
		local stat = stats[statName]
		if stat then
			stat:setCurrentValue(payload.value, stats)
		end
	end

	return stats :: Types.PlayerStats
end

-- =========================================
-- DELTA UPDATE SYSTEM (More Efficient)
-- =========================================

-- Types of delta updates
StatTypeUtil.DeltaTypes = {
	MODIFIER_ADDED = "modifier_added",
	MODIFIER_REMOVED = "modifier_removed",
	MODIFIER_UPDATED = "modifier_updated",
	CURRENT_VALUE_CHANGED = "current_value_changed",
	BASE_VALUE_CHANGED = "base_value_changed",
	RESERVATION_ADDED = "reservation_added",
	RESERVATION_REMOVED = "reservation_removed",
	FULL_SYNC = "full_sync", -- Fallback for initial sync or major changes
	RESOURCE_STATE_CHANGED = "resource_state_changed",
	RESOURCE_EVENT = "resource_event",
}

-- Create a delta update for a specific change
function StatTypeUtil.createDelta(deltaType: string, statName: string, data: any)
	return {
		type = deltaType,
		stat = statName,
		timestamp = tick(),
		data = data,
	}
end

-- Create modifier delta
function StatTypeUtil.createModifierDelta(deltaType: string, statName: string, modifierObj: any)
	local payloadCopy = modifierObj.payload and table.clone(modifierObj.payload) or nil
	local strategyParamsCopy = modifierObj.strategyParams and table.clone(modifierObj.strategyParams) or nil
	local tagsCopy = modifierObj.tags and table.clone(modifierObj.tags) or nil
	local metadataCopy = modifierObj.metadata and table.clone(modifierObj.metadata) or nil

	return StatTypeUtil.createDelta(deltaType, statName, {
		source_id = modifierObj.source_id,
		value = modifierObj.value,
		type = modifierObj.type,
		description = modifierObj.description,
		isActive = modifierObj.isActive,
		modifierType = modifierObj.modifierType or "StatModifier",
		targetStat = modifierObj.targetStat, -- For PercentOfStatModifier
		strategyKind = modifierObj.strategyKind,
		payload = payloadCopy,
		strategyParams = strategyParamsCopy,
		tags = tagsCopy,
		stackGroup = modifierObj.stackGroup,
		priority = modifierObj.priority,
		metadata = metadataCopy,
		duration = modifierObj.duration,
		expiresAt = modifierObj.expiresAt,
	})
end

-- Create current value delta
function StatTypeUtil.createCurrentValueDelta(statName: string, newValue: number, maxValue: number?)
	return StatTypeUtil.createDelta(StatTypeUtil.DeltaTypes.CURRENT_VALUE_CHANGED, statName, {
		currentValue = newValue,
		maxValue = maxValue, -- Include max for UI percentage calculations
	})
end

-- Create base value delta
function StatTypeUtil.createBaseValueDelta(statName: string, newBaseValue: number)
	return StatTypeUtil.createDelta(StatTypeUtil.DeltaTypes.BASE_VALUE_CHANGED, statName, {
		baseValue = newBaseValue,
	})
end

-- Apply a delta to existing client stats (avoids recreation)
function StatTypeUtil.applyDelta(clientStats: Types.PlayerStats, delta: any): boolean
	local statName = delta.stat or delta.target
	local stat = clientStats[statName]
	if not stat then
		warn(`Delta update for unknown stat: {statName}`)
		return false
	end

	local deltaData = delta.data

	if delta.type == StatTypeUtil.DeltaTypes.MODIFIER_ADDED then
		local modifierData = deltaData
		local modifier = ModifierFactories.hydrate(modifierData)
		if modifier then
			modifier.description = modifierData.description
			modifier.isActive = modifierData.isActive
			stat:addModifier(modifier)
		end
	elseif delta.type == StatTypeUtil.DeltaTypes.MODIFIER_REMOVED then
		stat:removeModifier(deltaData.source_id)
	elseif delta.type == StatTypeUtil.DeltaTypes.MODIFIER_UPDATED then
		stat:updateModifier(deltaData.source_id, deltaData.value)
	elseif delta.type == StatTypeUtil.DeltaTypes.CURRENT_VALUE_CHANGED then
		if StatTypeUtil.isPoolStat(stat) or StatTypeUtil.isResourceStat(stat) then
			stat:setCurrentValue(deltaData.currentValue, clientStats)
		end
	elseif delta.type == StatTypeUtil.DeltaTypes.BASE_VALUE_CHANGED then
		stat:setBaseValue(deltaData.baseValue)
	elseif delta.type == StatTypeUtil.DeltaTypes.RESERVATION_ADDED then
		if StatTypeUtil.isPoolStat(stat) or StatTypeUtil.isResourceStat(stat) then
			stat:addReservation(deltaData)
		end
	elseif delta.type == StatTypeUtil.DeltaTypes.RESERVATION_REMOVED then
		if StatTypeUtil.isPoolStat(stat) or StatTypeUtil.isResourceStat(stat) then
			stat:removeReservation(deltaData.source_id)
		end
	elseif delta.type == StatTypeUtil.DeltaTypes.RESOURCE_STATE_CHANGED then
		if StatTypeUtil.isResourceStat(stat) then
			stat:applyMetadataSnapshot(deltaData)
		end
	elseif delta.type == StatTypeUtil.DeltaTypes.RESOURCE_EVENT then
		if StatTypeUtil.isResourceStat(stat) and deltaData then
			stat:applyRemoteEvent(deltaData.event, deltaData.data)
		end
	else
		warn(`Unknown delta type: {delta.type}`)
		return false
	end

	return true
end

-- Usage examples:
--[[
local playerStat = StatsManager.getStat(player, "Health")

if StatTypeUtil.isPoolStat(playerStat) then
	-- This is a pool stat
	-- Current: playerStat:getCurrentValue()
	-- Max: playerStat:getMaxValue()
else
	-- This is a static stat
	-- Value: playerStat:getValue()
end

-- Or using stat name
if StatTypeUtil.isPoolName("Health") then
	-- Health is a pool type
end
]]

return StatTypeUtil
