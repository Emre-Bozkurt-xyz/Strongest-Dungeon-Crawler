-- Server-side stat management system for players and NPCs
-- Handles all stat modifications and syncing to clients (players only receive dispatcher deltas)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Registrar = require(ServerScriptService.Server.Services.Registrar)
local Networking = require(ReplicatedStorage.Shared.Networking)
local StatsConfig = require(script.Parent.Config.StatsConfig)
local StatsMediator = require(script.Parent.StatsMediator)
local Types = require(game.ReplicatedStorage.Shared.StatTypes)
local StatTypeUtil = require(ReplicatedStorage.Shared.StatTypeUtil)

local DEBUG = false

local profilingEnabled = false

type ProfileToken = { label: string, start: number }

local function profileBegin(label: string): ProfileToken?
	if not profilingEnabled then
		return nil
	end
	return {
		label = label,
		start = os.clock(),
	}
end

local function profileEnd(token: ProfileToken?)
	if not token then
		return
	end
	local durationMs = (os.clock() - token.start) * 1000
	print(string.format("[StatsManager][PROFILE] %s took %.3f ms", token.label, durationMs))
end

local function debugLog(...)
	if DEBUG then
		print("[StatsManager]", ...)
	end
end

-- Import types from central location
type EntityStats = Types.EntityStats
type StatType = Types.StatType
type StaticStatType = Types.StaticStatType
type PoolType = Types.PoolType
type ResourceType = Types.ResourceStatType

type Delta = {
	system: string,
	type: string,
	target: string,
	data: any,
	timestamp: number,
}

export type RegisterOptions = {
	stats: EntityStats?,
	configure: ((EntityStats) -> ())?,
	skipSync: boolean?,
}

type MediatorQueryOptionsInternal = StatsMediator.QueryOptions

export type MediatorQueryOptions = MediatorQueryOptionsInternal
export type QueryOptions = MediatorQueryOptionsInternal

local StatsManager = {}

-- EntityID to EntityStats map
local entityStats: { [string]: EntityStats } = {}

local function cloneOptions(source: MediatorQueryOptionsInternal?): MediatorQueryOptionsInternal
	local target: MediatorQueryOptionsInternal = {}
	if not source then
		return target
	end
	for key, value in pairs(source) do
		(target :: any)[key] = value
	end
	return target
end

local function mergeQueryOptions(
	baseContext: string,
	baseCacheKey: string,
	options: MediatorQueryOptionsInternal?
): MediatorQueryOptionsInternal
	local merged = cloneOptions(options)
	if not merged.context then
		merged.context = baseContext
	end
	if not merged.cacheKey then
		merged.cacheKey = baseCacheKey
	end
	if merged.event == nil then
		merged.event = merged.context
	end
	return merged
end

type PoolOperationMetadata = { [string]: any }

type PoolOperationContext = {
	entityId: string,
	stats: EntityStats,
	basePoolName: PoolType,
	currentPoolName: PoolType,
	pool: any,
	options: MediatorQueryOptions,
	metadata: PoolOperationMetadata,
	applyOverride: (string?) -> boolean,
}

export type PoolCostResolution = {
	originalPool: PoolType,
	poolName: PoolType,
	finalCost: number,
	metadata: PoolOperationMetadata,
	currentValue: number,
	maxValue: number,
}

local RESOURCE_TICK_INTERVAL = 0.1
local RESOURCE_DELTA_EPSILON = 1e-4
local resourceAccumulator = 0

-- Dispatcher channel wiring
local STATS_CHANNEL_NAME = "Stats"
local dispatcher = Networking.server()
local dispatcherAny = dispatcher :: any
dispatcher:_ensureChannel(STATS_CHANNEL_NAME)

-- Helper: send a delta to a player
local function sendStatDelta(entityId: string, deltaType: string, target: string, data: any)
	if not Registrar.isPlayerEntity(entityId) then
		return
	end
	local player = Registrar.getPlayerById(entityId)
	local delta: Delta = {
		system = "stats",
		type = deltaType,
		target = target,
		data = data,
		timestamp = os.clock(),
	}
	debugLog("Emit delta", delta.type, delta.target, player and player.Name or "<unknown>")
	dispatcherAny:emit("StatsDelta", delta, {
		targets = player,
	})
end

-- Helper: send full sync
local function sendFullSync(entityId: string)
	if not Registrar.isPlayerEntity(entityId) then
		return
	end
	local player = Registrar.getPlayerById(entityId)
	local stats = entityStats[entityId]
	if not stats then
		return
	end
	local serialized = StatTypeUtil.serializeStats(stats)
	local delta: Delta = {
		system = "stats",
		type = StatTypeUtil.DeltaTypes.FULL_SYNC,
		target = "ALL_DATA",
		data = serialized,
		timestamp = os.clock(),
	}
	debugLog("Emit full sync", player and player.Name)
	local profileToken = profileBegin("sendFullSync")
	dispatcherAny:emit("StatsDelta", delta, {
		targets = player,
	})
	profileEnd(profileToken)
end

local function sendResourceMetadata(entityId: string, resourceName: string, resourceStat: any)
	if not Registrar.isPlayerEntity(entityId) then
		return
	end
	sendStatDelta(
		entityId,
		StatTypeUtil.DeltaTypes.RESOURCE_STATE_CHANGED,
		resourceName,
		resourceStat:getMetadataSnapshot()
	)
end

local function propagateResourceEvents(entityId: string, resourceName: string, resourceStat: any)
	local events = resourceStat:consumeQueuedEvents()
	if not events or #events == 0 then
		return
	end

	local metadataDirty = false
	for _, eventPayload in ipairs(events) do
		if eventPayload.event == "valueChanged" then
			continue
		end

		if eventPayload.event == "metadataChanged" then
			metadataDirty = true
		elseif Registrar.isPlayerEntity(entityId) then
			sendStatDelta(entityId, StatTypeUtil.DeltaTypes.RESOURCE_EVENT, resourceName, eventPayload)
		end
	end

	if metadataDirty then
		sendResourceMetadata(entityId, resourceName, resourceStat)
	end
end

local function getResourceStat(entityId: string, resourceName: ResourceType): (any?, EntityStats?)
	local stats = entityStats[entityId]
	if not stats then
		warn(`Attempted to access resource {resourceName} for entity {entityId} with no stats initialized`)
		return nil, nil
	end
	local resource = (stats :: any)[resourceName]
	if not resource or not StatTypeUtil.isResourceStat(resource) then
		warn(`Resource {resourceName} not found for entity {entityId}`)
		return nil, stats
	end
	return resource, stats
end

local function processResourceTick(deltaTime: number)
	if deltaTime <= 0 then
		return
	end
	for entityId, stats in pairs(entityStats) do
		for statName, stat in pairs(stats) do
			if StatTypeUtil.isResourceStat(stat) then
				local changed = stat:tick(deltaTime, stats)
				if changed and Registrar.isPlayerEntity(entityId) then
					sendStatDelta(entityId, StatTypeUtil.DeltaTypes.CURRENT_VALUE_CHANGED, statName, {
						currentValue = stat:getCurrentValue(),
						maxValue = stat:getMaxValue(stats),
					})
				end
				propagateResourceEvents(entityId, statName, stat)
			end
		end
	end
end

function StatsManager.isRegistered(entityId: string): boolean
	return entityStats[entityId] ~= nil
end

function StatsManager.register(entityId: string, options: RegisterOptions?): EntityStats
	local existing = entityStats[entityId]
	if existing then
		StatsMediator.attach(entityId, existing)
		if options and options.configure then
			options.configure(existing)
			StatsMediator.invalidateAll(entityId)
		end
		if Registrar.isPlayerEntity(entityId) and not (options and options.skipSync) then
			sendFullSync(entityId)
		end
		return existing
	end

	local stats = if options and options.stats then options.stats else StatsConfig.createDefaultStats()
	entityStats[entityId] = stats
	StatsMediator.attach(entityId, stats)

	if options and options.configure then
		options.configure(stats)
		StatsMediator.invalidateAll(entityId)
	end

	local player = Registrar.getPlayerById(entityId)

	if player and not (options and options.skipSync) then
		sendFullSync(entityId)
		print(`Initialized stats for player: {player.Name}`)
	end

	return stats
end

function StatsManager.unregister(entityId: string): boolean
	if not entityStats[entityId] then
		return false
	end
	entityStats[entityId] = nil
	StatsMediator.detach(entityId)
	return true
end

-- Initialize stats for a new player
function StatsManager.initializePlayerStats(player: Player)
	if StatsManager.isRegistered(Registrar.getPlayerId(player) or "") then
		error("Player stats already initialized")
		return
	end
	StatsManager.register(Registrar.getPlayerId(player) or error("Player has no registered EntityId"))
end

-- Clean up when player leaves
function StatsManager.cleanupPlayerStats(player: Player)
	local removed = StatsManager.unregister(Registrar.getPlayerId(player) or error("Player has no registered EntityId"))
	if removed then
		print(`Cleaned up stats for player: {player.Name}`)
	end
end

-- Set base value for stats or pools
function StatsManager.setBaseStat(entityId: string, statName: StatType, newValue: number)
	local stats = entityStats[entityId]
	if not stats then
		warn(`Attempted to set stat for entity {entityId} who has no stats initialized`)
		return false
	end

	local validatedValue = StatsConfig.validateStatValue(newValue)
	local stat = (stats :: any)[statName]

	if not stat then
		warn(`Stat {statName} not found for entity {entityId}`)
		return false
	end

	stat:setBaseValue(validatedValue)
	StatsMediator.invalidateStat(entityId, statName)
	if Registrar.isPlayerEntity(entityId) then
		sendStatDelta(entityId, StatTypeUtil.DeltaTypes.BASE_VALUE_CHANGED, statName, { baseValue = validatedValue })
	end
	return true
end

local function preparePoolOperation(
	entityId: string,
	poolName: PoolType,
	amount: number,
	options: MediatorQueryOptionsInternal?,
	baseContext: string?,
	cacheKey: string?
): PoolOperationContext?
	local stats = entityStats[entityId]
	if not stats then
		warn(`Attempted to access pool {poolName} for entity {entityId} who has no stats initialized`)
		return nil
	end

	local pool = stats[poolName]
	if not pool or not StatTypeUtil.isPoolStat(pool) then
		warn(`Pool {poolName} not found for entity {entityId}`)
		return nil
	end

	local resolvedOptions = mergeQueryOptions(baseContext or "removeFromPool", cacheKey or "removed", options)
	resolvedOptions.cacheEnabled = false
	resolvedOptions.originalStat = resolvedOptions.originalStat or poolName

	local metadata: PoolOperationMetadata = if resolvedOptions.metadata
		then resolvedOptions.metadata
		else {} :: PoolOperationMetadata
	resolvedOptions.metadata = metadata

	local context: PoolOperationContext = {
		entityId = entityId,
		stats = stats,
		basePoolName = poolName,
		currentPoolName = poolName,
		pool = pool,
		options = resolvedOptions,
		metadata = metadata,
		applyOverride = function(_target: string?)
			return true
		end,
	}

	metadata.originalStat = metadata.originalStat or poolName
	metadata.targetStat = metadata.targetStat or poolName
	metadata.pool = metadata.pool or poolName
	metadata.baseCost = metadata.baseCost or amount
	metadata.finalCost = nil

	local function applyOverride(target: string?): boolean
		if not target or target == context.currentPoolName then
			return true
		end
		local overridePool = stats[target]
		if not overridePool or not StatTypeUtil.isPoolStat(overridePool) then
			warn(`Override stat {target} for entity {entityId} is not a valid pool; keeping {context.currentPoolName}`)
			return false
		end
		context.pool = overridePool
		context.currentPoolName = target :: PoolType
		if context.currentPoolName ~= context.basePoolName then
			resolvedOptions.overrideStat = context.currentPoolName
			metadata.overrideStat = context.currentPoolName
		else
			resolvedOptions.overrideStat = nil
			metadata.overrideStat = nil
		end
		metadata.targetStat = context.currentPoolName
		metadata.pool = context.currentPoolName
		return true
	end

	context.applyOverride = applyOverride
	applyOverride(resolvedOptions.overrideStat)

	if context.currentPoolName == context.basePoolName then
		metadata.overrideStat = nil
	end

	return context
end

local function executePoolOperation(
	context: PoolOperationContext,
	amount: number,
	executor: (number) -> any
): (any, boolean)
	local metadata = context.metadata
	metadata.baseCost = metadata.baseCost or amount
	metadata.finalCost = nil

	local executed = false
	local statTypeForQuery = context.currentPoolName
	local result = StatsMediator.resolve(context.entityId, statTypeForQuery, function()
		local requestedOverride = context.options.overrideStat
		if requestedOverride and requestedOverride ~= context.currentPoolName then
			local applied = context.applyOverride(requestedOverride)
			if not applied then
				if context.currentPoolName ~= context.basePoolName then
					context.options.overrideStat = context.currentPoolName
					metadata.overrideStat = context.currentPoolName
				else
					context.options.overrideStat = nil
					metadata.overrideStat = nil
				end
			end
		end

		local finalAmount = amount
		if metadata.adjustedCost ~= nil then
			finalAmount = metadata.adjustedCost
		end

		if context.currentPoolName ~= context.basePoolName then
			metadata.overrideStat = context.currentPoolName
		elseif metadata.overrideStat ~= nil then
			metadata.overrideStat = nil
		end
		metadata.targetStat = context.currentPoolName
		metadata.pool = context.currentPoolName
		metadata.finalCost = finalAmount
		executed = true
		return executor(finalAmount)
	end, context.options)

	return result, executed
end

function StatsManager.addToPool(entityId: string, poolName: PoolType, amount: number): boolean
	local stats = entityStats[entityId]
	if not stats then
		warn(`Attempted to add to pool for entity {entityId} who has no stats initialized`)
		return false
	end

	local pool = (stats :: any)[poolName]
	if not pool or not StatTypeUtil.isPoolStat(pool) then
		warn(`Pool {poolName} not found for entity {entityId}`)
		return false
	end

	local added = pool:addToCurrentValue(amount)
	if added and Players:GetPlayerFromCharacter(entityId) then
		sendStatDelta(entityId, StatTypeUtil.DeltaTypes.CURRENT_VALUE_CHANGED, poolName, {
			currentValue = pool:getCurrentValue(),
			maxValue = pool:getValue(stats),
		})
	end

	return added
end

function StatsManager.removeFromPool(
	entityId: string,
	poolName: PoolType,
	amount: number,
	options: MediatorQueryOptionsInternal?
): boolean
	local context = preparePoolOperation(entityId, poolName, amount, options, "removeFromPool", "removed")
	if not context then
		return false
	end

	local removed, executed = executePoolOperation(context, amount, function(finalAmount)
		return context.pool:removeFromCurrentValue(finalAmount, context.stats)
	end)

	
	if executed and removed ~= nil and Registrar.isPlayerEntity(entityId) then
		sendStatDelta(entityId, StatTypeUtil.DeltaTypes.CURRENT_VALUE_CHANGED, context.currentPoolName, {
			currentValue = context.pool:getCurrentValue(),
			maxValue = context.pool:getValue(context.stats),
		})
	end
	
	return removed ~= nil
end

function StatsManager.resolvePoolCost(
	entityId: string,
	poolName: PoolType,
	amount: number,
	options: MediatorQueryOptionsInternal?
): PoolCostResolution?
	local context = preparePoolOperation(entityId, poolName, amount, options, "resolvePoolCost", "costPreview")
	if not context then
		return nil
	end

	local _, executed = executePoolOperation(context, amount, function(finalAmount)
		return finalAmount
	end)

	if not executed then
		return nil
	end

	local finalCost = context.metadata.finalCost or amount
	local currentValue = if context.pool.getCurrentValue then context.pool:getCurrentValue() else 0

	local maxValue = 0
	if context.pool.getValue then
		maxValue = context.pool:getValue(context.stats)
	elseif context.pool.getMaxValue then
		maxValue = context.pool:getMaxValue(context.stats)
	end

	return {
		originalPool = context.basePoolName,
		poolName = context.currentPoolName,
		finalCost = finalCost,
		metadata = context.metadata,
		currentValue = currentValue,
		maxValue = maxValue,
	}
end

function StatsManager.addReservation(entityId: string, poolName: PoolType, reservation)
	local stats = entityStats[entityId]
	if not stats then
		return false
	end
	local pool = (stats :: any)[poolName]
	if not pool or not pool.addReservation then
		return false
	end
	pool:addReservation(reservation)
	StatsMediator.invalidateStat(entityId, poolName)
	if Players:GetPlayerFromCharacter(entityId) then
		sendStatDelta(entityId, StatTypeUtil.DeltaTypes.RESERVATION_ADDED, poolName, reservation)
	end
	return true
end

function StatsManager.removeReservation(entityId: string, poolName: PoolType, source_id: string)
	local stats = entityStats[entityId]
	if not stats then
		return false
	end
	local pool = (stats :: any)[poolName]
	if not pool or not pool.removeReservation then
		return false
	end
	local removed = pool:removeReservation(source_id)
	if not removed then
		return false
	end
	StatsMediator.invalidateStat(entityId, poolName)
	if Players:GetPlayerFromCharacter(entityId) then
		sendStatDelta(entityId, StatTypeUtil.DeltaTypes.RESERVATION_REMOVED, poolName, { source_id = source_id })
	end
	return true
end

function StatsManager.addToResource(entityId: string, resourceName: ResourceType, amount: number): boolean
	local resource, stats = getResourceStat(entityId, resourceName)
	if not resource or not stats then
		return false
	end

	local previousValue = resource:getCurrentValue()
	local newValue = resource:addToCurrentValue(amount, stats)
	local changed = math.abs(newValue - previousValue) > RESOURCE_DELTA_EPSILON
	if changed and Players:GetPlayerFromCharacter(entityId) then
		sendStatDelta(entityId, StatTypeUtil.DeltaTypes.CURRENT_VALUE_CHANGED, resourceName, {
			currentValue = newValue,
			maxValue = resource:getMaxValue(stats),
		})
	end

	propagateResourceEvents(entityId, resourceName, resource)
	return changed
end

function StatsManager.removeFromResource(entityId: string, resourceName: ResourceType, amount: number): boolean
	return StatsManager.addToResource(entityId, resourceName, -amount)
end

function StatsManager.setResourceValue(entityId: string, resourceName: ResourceType, value: number): boolean
	local resource, stats = getResourceStat(entityId, resourceName)
	if not resource or not stats then
		return false
	end

	local previousValue = resource:getCurrentValue()
	local newValue = resource:setCurrentValue(value, stats)
	local changed = math.abs(newValue - previousValue) > RESOURCE_DELTA_EPSILON
	if changed and Players:GetPlayerFromCharacter(entityId) then
		sendStatDelta(entityId, StatTypeUtil.DeltaTypes.CURRENT_VALUE_CHANGED, resourceName, {
			currentValue = newValue,
			maxValue = resource:getMaxValue(stats),
		})
	end

	propagateResourceEvents(entityId, resourceName, resource)
	return changed
end

function StatsManager.setResourceRegeneration(entityId: string, resourceName: ResourceType, rate: number): boolean
	local resource, _ = getResourceStat(entityId, resourceName)
	if not resource then
		return false
	end

	local previousRate = resource:getRegenerationRate()
	resource:setRegenerationRate(rate)
	local changed = math.abs(previousRate - rate) > RESOURCE_DELTA_EPSILON
	propagateResourceEvents(entityId, resourceName, resource)
	return changed
end

function StatsManager.pauseResourceRegeneration(entityId: string, resourceName: ResourceType, duration: number?)
	local resource, _ = getResourceStat(entityId, resourceName)
	if not resource then
		return false
	end
	resource:pauseRegeneration(duration)
	propagateResourceEvents(entityId, resourceName, resource)
	return true
end

function StatsManager.resumeResourceRegeneration(entityId: string, resourceName: ResourceType)
	local resource, _ = getResourceStat(entityId, resourceName)
	if not resource then
		return false
	end
	resource:resumeRegeneration()
	propagateResourceEvents(entityId, resourceName, resource)
	return true
end

function StatsManager.setResourceDepletionThreshold(entityId: string, resourceName: ResourceType, threshold: number)
	local resource, _ = getResourceStat(entityId, resourceName)
	if not resource then
		return false
	end
	resource:setDepletionThreshold(threshold)
	propagateResourceEvents(entityId, resourceName, resource)
	return true
end

function StatsManager.addResourceThreshold(entityId: string, resourceName: ResourceType, thresholdId: string, config)
	local resource, _ = getResourceStat(entityId, resourceName)
	if not resource then
		return false
	end
	resource:addThreshold(thresholdId, config)
	propagateResourceEvents(entityId, resourceName, resource)
	return true
end

function StatsManager.removeResourceThreshold(entityId: string, resourceName: ResourceType, thresholdId: string)
	local resource, _ = getResourceStat(entityId, resourceName)
	if not resource then
		return false
	end
	local removed = resource:removeThreshold(thresholdId)
	if removed then
		propagateResourceEvents(entityId, resourceName, resource)
	end
	return removed
end

function StatsManager.onResourceEvent(
	entityId: string,
	resourceName: ResourceType,
	eventName: string,
	callbackId: string,
	callback: (any, any) -> ()
)
	local resource, _ = getResourceStat(entityId, resourceName)
	if not resource then
		return false
	end
	resource:registerCallback(eventName, callbackId, callback)
	return true
end

function StatsManager.offResourceEvent(
	entityId: string,
	resourceName: ResourceType,
	eventName: string,
	callbackId: string
)
	local resource, _ = getResourceStat(entityId, resourceName)
	if not resource then
		return false
	end
	resource:unregisterCallback(eventName, callbackId)
	return true
end

function StatsManager.getResourceCurrentValue(
	entityId: string,
	resourceName: ResourceType,
	queryOptions: MediatorQueryOptionsInternal?
): number?
	local resource, _ = getResourceStat(entityId, resourceName)
	if not resource then
		return nil
	end
	local resolvedOptions = mergeQueryOptions("getResourceCurrentValue", "current", queryOptions)
	if resolvedOptions.cacheEnabled == nil then
		resolvedOptions.cacheEnabled = false
	end
	return StatsMediator.resolve(entityId, resourceName, function()
		return resource:getCurrentValue()
	end, resolvedOptions)
end

function StatsManager.getResourceMaxValue(
	entityId: string,
	resourceName: ResourceType,
	queryOptions: MediatorQueryOptionsInternal?
): number?
	local resource, stats = getResourceStat(entityId, resourceName)
	if not resource or not stats then
		return nil
	end
	local resolvedOptions = mergeQueryOptions("getResourceMaxValue", "max", queryOptions)
	return StatsMediator.resolve(entityId, resourceName, function()
		return resource:getMaxValue(stats)
	end, resolvedOptions)
end

function StatsManager.addModifier(entityId: string, statType: StatType, modifier)
	local stats = entityStats[entityId]
	if not stats then
		warn(`Attempted to add modifier for entity {entityId} who has no stats initialized`)
		return false
	end
	local stat = stats[statType]
	stat:addModifier(modifier)
	StatsMediator.invalidateStat(entityId, statType)
	StatsManager.invalidateAllCaches(entityId)
	if Registrar.isPlayerEntity(entityId) then
		sendStatDelta(entityId, StatTypeUtil.DeltaTypes.MODIFIER_ADDED, statType, modifier)
	end
	return true
end

function StatsManager.removeModifier(entityId: string, statType: StatType, source_id: string)
	local stats = entityStats[entityId]
	if not stats then
		warn(`Attempted to remove modifier for entity {entityId} who has no stats initialized`)
		return false
	end
	local stat = stats[statType]
	local removed = stat:removeModifier(source_id)
	if removed then
		StatsMediator.invalidateStat(entityId, statType)
		StatsManager.invalidateAllCaches(entityId)
		if Registrar.isPlayerEntity(entityId) then
			sendStatDelta(entityId, StatTypeUtil.DeltaTypes.MODIFIER_REMOVED, statType, { source_id = source_id })
		end
	end
	return removed
end

function StatsManager.updateModifier(entityId: string, statType: StatType, source_id: string, newValue: number)
	local stats = entityStats[entityId]
	if not stats then
		warn(`Attempted to update modifier for entity {entityId} who has no stats initialized`)
		return false
	end
	local stat = stats[statType]
	if not stat then
		warn(`Stat {statType} not found for entity {entityId}`)
		return false
	end
	local success = stat:updateModifier(source_id, newValue)
	if success then
		StatsMediator.invalidateStat(entityId, statType)
		StatsManager.invalidateAllCaches(entityId)
		if Registrar.isPlayerEntity(entityId) then
			sendStatDelta(
				entityId,
				StatTypeUtil.DeltaTypes.MODIFIER_UPDATED,
				statType,
				{ source_id = source_id, value = newValue }
			)
		end
		return true
	end
	warn(`Modifier '{source_id}' not found in {entityId}'s {statType}`)
	return false
end

function StatsManager.hasModifier(entityId: string, statType: StatType, source_id: string): boolean
	local stats = entityStats[entityId]
	if not stats then
		return false
	end
	local stat = stats[statType]
	if not stat then
		return false
	end
	for _, modifier in ipairs(stat.modifiers) do
		if modifier.source_id == source_id then
			return true
		end
	end
	return false
end

function StatsManager.getStat(entityId: string, statType: StatType): Types.StatInstance?
	local stats = entityStats[entityId]
	if not stats then
		return nil
	end
	return stats[statType]
end

function StatsManager.getStatValue(
	entityId: string,
	statType: StatType,
	queryOptions: MediatorQueryOptionsInternal?
): number?
	local stats = entityStats[entityId]
	if not stats then
		return nil
	end
	local stat = stats[statType]
	if not stat then
		return nil
	end
	local resolvedOptions = mergeQueryOptions("getStatValue", "value", queryOptions)
	return StatsMediator.resolve(entityId, statType, function()
		return stat:getValue(stats)
	end, resolvedOptions)
end

function StatsManager.getAllStats(entityId: string): EntityStats?
	return entityStats[entityId]
end

-- Convenience getters for pool stats (current vs max)
function StatsManager.getPoolCurrentValue(
	entityId: string,
	poolName: PoolType,
	queryOptions: MediatorQueryOptionsInternal?
): number?
	local stats = entityStats[entityId]
	if not stats then
		return nil
	end
	local pool = (stats :: any)[poolName]
	if pool and pool.getCurrentValue then
		local resolvedOptions = mergeQueryOptions("getPoolCurrentValue", "current", queryOptions)
		if resolvedOptions.cacheEnabled == nil then
			resolvedOptions.cacheEnabled = false
		end
		return StatsMediator.resolve(entityId, poolName, function()
			return pool:getCurrentValue()
		end, resolvedOptions)
	end
	return nil
end

function StatsManager.getPoolMaxValue(
	entityId: string,
	poolName: PoolType,
	queryOptions: MediatorQueryOptionsInternal?
): number?
	local stats = entityStats[entityId]
	if not stats then
		return nil
	end
	local pool = (stats :: any)[poolName]
	if not pool or not pool.getValue then
		return nil
	end
	local resolvedOptions = mergeQueryOptions("getPoolMaxValue", "max", queryOptions)
	return StatsMediator.resolve(entityId, poolName, function()
		return pool:getValue(stats)
	end, resolvedOptions)
end

function StatsManager.getPoolPercentage(entityId: string, poolName: PoolType): number?
	local stats = entityStats[entityId]
	if not stats then
		return nil
	end
	local pool = (stats :: any)[poolName]
	if pool and pool.getPercentage then
		return pool:getPercentage(stats)
	end
	return nil
end

function StatsManager.invalidateAllCaches(entityId: string)
	local stats = entityStats[entityId]
	if not stats then
		return
	end
	local profileToken = profileBegin("invalidateAllCaches")
	for _, stat in pairs(stats) do
		if stat.invalidateCache then
			stat:invalidateCache()
		end
	end
	profileEnd(profileToken)
	StatsMediator.invalidateAll(entityId)
end

function StatsManager.setProfilingEnabled(enabled: boolean)
	profilingEnabled = enabled
end

function StatsManager.resetStats(entityId: string)
	if not entityStats[entityId] then
		warn(`Attempted to reset stats for entity {entityId} who has no stats initialized`)
		return false
	end
	local stats = StatsConfig.createDefaultStats()
	entityStats[entityId] = stats
	StatsMediator.attach(entityId, stats)
	StatsMediator.invalidateAll(entityId)

	local player = Registrar.getPlayerById(entityId)

	if player then
		sendFullSync(entityId)
		print(`Reset stats for player: {player.Name}`)
	else
		local model = Registrar.getEntityById(entityId)
		print(`Reset stats for entity: {model and model.Name}`)
	end
	return true
end

function StatsManager.emitDelta(entityId: string, deltaType: string, target: string, data: any)
	sendStatDelta(entityId, deltaType, target, data)
end

RunService.Heartbeat:Connect(function(deltaTime)
	resourceAccumulator += deltaTime
	if resourceAccumulator >= RESOURCE_TICK_INTERVAL then
		processResourceTick(resourceAccumulator)
		resourceAccumulator = 0
	end
end)

-- Request handler (C->S): return full serialized data
local _statsRequestDisconnect = dispatcherAny:onRequest("StatsRequest", function(_payload, _meta, context)
	local player = context.player
	if not player then
		warn("StatsManager received StatsRequest without player context")
		return nil
	end

	local entityId = Registrar.getPlayerId(player)

	if not StatsManager.isRegistered(entityId) then
		StatsManager.register(entityId)
	end
	local stats = entityStats[entityId]
	if not stats then
		return nil
	end
	debugLog("Request full snapshot", player.Name)
	return StatTypeUtil.serializeStats(stats)
end)

print("StatsManager initialized with custom networking")
return StatsManager
