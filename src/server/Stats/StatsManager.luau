--!strict
-- Server-side stat management system for players and NPCs
-- Handles all stat modifications and syncing to clients (players only receive dispatcher deltas)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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
type PlayerStats = Types.PlayerStats
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
	stats: PlayerStats?,
	configure: ((PlayerStats) -> ())?,
	skipSync: boolean?,
}

local StatsManager = {}
local entityStats: { [Instance]: PlayerStats } = {}

local RESOURCE_TICK_INTERVAL = 0.1
local RESOURCE_DELTA_EPSILON = 1e-4
local resourceAccumulator = 0

-- Dispatcher channel wiring
local STATS_CHANNEL_NAME = "Stats"
local dispatcher = Networking.server()
local dispatcherAny = dispatcher :: any
dispatcher:_ensureChannel(STATS_CHANNEL_NAME)

-- Helper: send a delta to a player
local function sendStatDelta(entity: Instance, deltaType: string, target: string, data: any)
	if not entity:IsA("Player") then
		return
	end
	local player = entity :: Player
	local delta: Delta = {
		system = "stats",
		type = deltaType,
		target = target,
		data = data,
		timestamp = os.clock(),
	}
	debugLog("Emit delta", delta.type, delta.target, entity.Name)
	dispatcherAny:emit("StatsDelta", delta, {
		targets = player,
	})
end

-- Helper: send full sync
local function sendFullSync(entity: Instance)
	if not entity:IsA("Player") then
		return
	end
	local player = entity :: Player
	local stats = entityStats[player]
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
	debugLog("Emit full sync", entity.Name)
	local profileToken = profileBegin("sendFullSync")
	dispatcherAny:emit("StatsDelta", delta, {
		targets = player,
	})
	profileEnd(profileToken)
end

local function sendResourceMetadata(entity: Instance, resourceName: string, resourceStat: any)
	if not entity:IsA("Player") then
		return
	end
	sendStatDelta(entity, StatTypeUtil.DeltaTypes.RESOURCE_STATE_CHANGED, resourceName, resourceStat:getMetadataSnapshot())
end

local function propagateResourceEvents(entity: Instance, resourceName: string, resourceStat: any)
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
		elseif entity:IsA("Player") then
			sendStatDelta(entity, StatTypeUtil.DeltaTypes.RESOURCE_EVENT, resourceName, eventPayload)
		end
	end

	if metadataDirty then
		sendResourceMetadata(entity, resourceName, resourceStat)
	end
end

local function getResourceStat(entity: Instance, resourceName: ResourceType): (any?, PlayerStats?)
	local stats = entityStats[entity]
	if not stats then
		warn(`Attempted to access resource {resourceName} for entity {entity.Name} with no stats initialized`)
		return nil, nil
	end
	local resource = (stats :: any)[resourceName]
	if not resource or not StatTypeUtil.isResourceStat(resource) then
		warn(`Resource {resourceName} not found for entity {entity.Name}`)
		return nil, stats
	end
	return resource, stats
end

local function processResourceTick(deltaTime: number)
	if deltaTime <= 0 then
		return
	end
	for entity, stats in pairs(entityStats) do
		for statName, stat in pairs(stats) do
			if StatTypeUtil.isResourceStat(stat) then
				local changed = stat:tick(deltaTime, stats)
				if changed and entity:IsA("Player") then
					sendStatDelta(entity, StatTypeUtil.DeltaTypes.CURRENT_VALUE_CHANGED, statName, {
						currentValue = stat:getCurrentValue(),
						maxValue = stat:getMaxValue(stats),
					})
				end
				propagateResourceEvents(entity, statName, stat)
			end
		end
	end
end

function StatsManager.isRegistered(entity: Instance): boolean
	return entityStats[entity] ~= nil
end

function StatsManager.register(entity: Instance, options: RegisterOptions?): PlayerStats
	local existing = entityStats[entity]
	if existing then
		StatsMediator.attach(entity, existing)
		if options and options.configure then
			options.configure(existing)
			StatsMediator.invalidateAll(entity)
		end
		if entity:IsA("Player") and not (options and options.skipSync) then
			sendFullSync(entity)
		end
		return existing
	end

	local stats = if options and options.stats then options.stats else StatsConfig.createDefaultStats()
	entityStats[entity] = stats
	StatsMediator.attach(entity, stats)

	if options and options.configure then
		options.configure(stats)
		StatsMediator.invalidateAll(entity)
	end

	if entity:IsA("Player") and not (options and options.skipSync) then
		sendFullSync(entity)
		print(`Initialized stats for player: {entity.Name}`)
	else
		print(`Initialized stats for entity: {entity:GetFullName()}`)
	end

	return stats
end

function StatsManager.unregister(entity: Instance): boolean
	if not entityStats[entity] then
		return false
	end
	entityStats[entity] = nil
	StatsMediator.detach(entity)
	return true
end

-- Initialize stats for a new player
local function initializePlayerStats(player: Player)
	StatsManager.register(player)
end

-- Clean up when player leaves
local function cleanupPlayerStats(player: Player)
	local removed = StatsManager.unregister(player)
	if removed then
		print(`Cleaned up stats for player: {player.Name}`)
	end
end

-- Set base value for stats or pools
function StatsManager.setBaseStat(entity: Instance, statName: StatType, newValue: number)
	local stats = entityStats[entity]
	if not stats then
		warn(`Attempted to set stat for entity {entity.Name} who has no stats initialized`)
		return false
	end

	local validatedValue = StatsConfig.validateStatValue(newValue)
	local stat = (stats :: any)[statName]

	if not stat then
		warn(`Stat {statName} not found for entity {entity.Name}`)
		return false
	end

	stat:setBaseValue(validatedValue)
	StatsMediator.invalidateStat(entity, statName)
	if entity:IsA("Player") then
		sendStatDelta(entity, StatTypeUtil.DeltaTypes.BASE_VALUE_CHANGED, statName, { baseValue = validatedValue })
	end
	return true
end

function StatsManager.addToPool(entity: Instance, poolName: PoolType, amount: number): boolean
	local stats = entityStats[entity]
	if not stats then
		warn(`Attempted to add to pool for entity {entity.Name} who has no stats initialized`)
		return false
	end

	local pool = (stats :: any)[poolName]
	if not pool or not StatTypeUtil.isPoolStat(pool) then
		warn(`Pool {poolName} not found for entity {entity.Name}`)
		return false
	end

	local added = pool:addToCurrentValue(amount)
	if added and entity:IsA("Player") then
		sendStatDelta(entity, StatTypeUtil.DeltaTypes.CURRENT_VALUE_CHANGED, poolName, {
			currentValue = pool:getCurrentValue(),
			maxValue = pool:getValue(stats),
		})
	end

	return added
end

function StatsManager.removeFromPool(entity: Instance, poolName: PoolType, amount: number)
	local stats = entityStats[entity]
	if not stats then
		warn(`Attempted to remove from pool for entity {entity.Name} who has no stats initialized`)
		return false
	end

	local pool = (stats :: any)[poolName]
	if not pool or not StatTypeUtil.isPoolStat(pool) then
		warn(`Pool {poolName} not found for entity {entity.Name}`)
		return false
	end

	local removed = pool:removeFromCurrentValue(amount)
	if removed and entity:IsA("Player") then
		sendStatDelta(entity, StatTypeUtil.DeltaTypes.CURRENT_VALUE_CHANGED, poolName, {
			currentValue = pool:getCurrentValue(),
			maxValue = pool:getValue(stats),
		})
	end

	return removed
end

function StatsManager.addReservation(entity: Instance, poolName: PoolType, reservation)
	local stats = entityStats[entity]
	if not stats then
		return false
	end
	local pool = (stats :: any)[poolName]
	if not pool or not pool.addReservation then
		return false
	end
	pool:addReservation(reservation)
	StatsMediator.invalidateStat(entity, poolName)
	if entity:IsA("Player") then
		sendStatDelta(entity, StatTypeUtil.DeltaTypes.RESERVATION_ADDED, poolName, reservation)
	end
	return true
end

function StatsManager.removeReservation(entity: Instance, poolName: PoolType, source_id: string)
	local stats = entityStats[entity]
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
	StatsMediator.invalidateStat(entity, poolName)
	if entity:IsA("Player") then
		sendStatDelta(entity, StatTypeUtil.DeltaTypes.RESERVATION_REMOVED, poolName, { source_id = source_id })
	end
	return true
end

function StatsManager.addToResource(entity: Instance, resourceName: ResourceType, amount: number): boolean
	local resource, stats = getResourceStat(entity, resourceName)
	if not resource or not stats then
		return false
	end

	local previousValue = resource:getCurrentValue()
	local newValue = resource:addToCurrentValue(amount, stats)
	local changed = math.abs(newValue - previousValue) > RESOURCE_DELTA_EPSILON
	if changed and entity:IsA("Player") then
		sendStatDelta(entity, StatTypeUtil.DeltaTypes.CURRENT_VALUE_CHANGED, resourceName, {
			currentValue = newValue,
			maxValue = resource:getMaxValue(stats),
		})
	end

	propagateResourceEvents(entity, resourceName, resource)
	return changed
end

function StatsManager.removeFromResource(entity: Instance, resourceName: ResourceType, amount: number): boolean
	return StatsManager.addToResource(entity, resourceName, -amount)
end

function StatsManager.setResourceValue(entity: Instance, resourceName: ResourceType, value: number): boolean
	local resource, stats = getResourceStat(entity, resourceName)
	if not resource or not stats then
		return false
	end

	local previousValue = resource:getCurrentValue()
	local newValue = resource:setCurrentValue(value, stats)
	local changed = math.abs(newValue - previousValue) > RESOURCE_DELTA_EPSILON
	if changed and entity:IsA("Player") then
		sendStatDelta(entity, StatTypeUtil.DeltaTypes.CURRENT_VALUE_CHANGED, resourceName, {
			currentValue = newValue,
			maxValue = resource:getMaxValue(stats),
		})
	end

	propagateResourceEvents(entity, resourceName, resource)
	return changed
end

function StatsManager.setResourceRegeneration(entity: Instance, resourceName: ResourceType, rate: number): boolean
	local resource, _ = getResourceStat(entity, resourceName)
	if not resource then
		return false
	end

	local previousRate = resource:getRegenerationRate()
	resource:setRegenerationRate(rate)
	local changed = math.abs(previousRate - rate) > RESOURCE_DELTA_EPSILON
	propagateResourceEvents(entity, resourceName, resource)
	return changed
end

function StatsManager.pauseResourceRegeneration(entity: Instance, resourceName: ResourceType, duration: number?)
	local resource, _ = getResourceStat(entity, resourceName)
	if not resource then
		return false
	end
	resource:pauseRegeneration(duration)
	propagateResourceEvents(entity, resourceName, resource)
	return true
end

function StatsManager.resumeResourceRegeneration(entity: Instance, resourceName: ResourceType)
	local resource, _ = getResourceStat(entity, resourceName)
	if not resource then
		return false
	end
	resource:resumeRegeneration()
	propagateResourceEvents(entity, resourceName, resource)
	return true
end

function StatsManager.setResourceDepletionThreshold(entity: Instance, resourceName: ResourceType, threshold: number)
	local resource, _ = getResourceStat(entity, resourceName)
	if not resource then
		return false
	end
	resource:setDepletionThreshold(threshold)
	propagateResourceEvents(entity, resourceName, resource)
	return true
end

function StatsManager.addResourceThreshold(entity: Instance, resourceName: ResourceType, thresholdId: string, config)
	local resource, _ = getResourceStat(entity, resourceName)
	if not resource then
		return false
	end
	resource:addThreshold(thresholdId, config)
	propagateResourceEvents(entity, resourceName, resource)
	return true
end

function StatsManager.removeResourceThreshold(entity: Instance, resourceName: ResourceType, thresholdId: string)
	local resource, _ = getResourceStat(entity, resourceName)
	if not resource then
		return false
	end
	local removed = resource:removeThreshold(thresholdId)
	if removed then
		propagateResourceEvents(entity, resourceName, resource)
	end
	return removed
end

function StatsManager.onResourceEvent(entity: Instance, resourceName: ResourceType, eventName: string, callbackId: string, callback: (any, any) -> ())
	local resource, _ = getResourceStat(entity, resourceName)
	if not resource then
		return false
	end
	resource:registerCallback(eventName, callbackId, callback)
	return true
end

function StatsManager.offResourceEvent(entity: Instance, resourceName: ResourceType, eventName: string, callbackId: string)
	local resource, _ = getResourceStat(entity, resourceName)
	if not resource then
		return false
	end
	resource:unregisterCallback(eventName, callbackId)
	return true
end

function StatsManager.getResourceCurrentValue(entity: Instance, resourceName: ResourceType): number?
	local resource, _ = getResourceStat(entity, resourceName)
	if not resource then
		return nil
	end
	return resource:getCurrentValue()
end

function StatsManager.getResourceMaxValue(entity: Instance, resourceName: ResourceType): number?
	local resource, stats = getResourceStat(entity, resourceName)
	if not resource or not stats then
		return nil
	end
	return StatsMediator.resolve(entity, resourceName, function()
		return resource:getMaxValue(stats)
	end, {
		context = "getResourceMaxValue",
		cacheKey = "max",
	})
end

function StatsManager.addModifier(entity: Instance, statType: StatType, modifier)
	local stats = entityStats[entity]
	if not stats then
		warn(`Attempted to add modifier for entity {entity.Name} who has no stats initialized`)
		return false
	end
	local stat = stats[statType]
	stat:addModifier(modifier)
	StatsMediator.invalidateStat(entity, statType)
	StatsManager.invalidateAllCaches(entity)
	if entity:IsA("Player") then
		sendStatDelta(entity, StatTypeUtil.DeltaTypes.MODIFIER_ADDED, statType, modifier)
	end
	return true
end

function StatsManager.removeModifier(entity: Instance, statType: StatType, source_id: string)
	local stats = entityStats[entity]
	if not stats then
		warn(`Attempted to remove modifier for entity {entity.Name} who has no stats initialized`)
		return false
	end
	local stat = stats[statType]
	local removed = stat:removeModifier(source_id)
	if removed then
		StatsMediator.invalidateStat(entity, statType)
		StatsManager.invalidateAllCaches(entity)
		if entity:IsA("Player") then
			sendStatDelta(entity, StatTypeUtil.DeltaTypes.MODIFIER_REMOVED, statType, { source_id = source_id })
		end
	end
	return removed
end

function StatsManager.updateModifier(entity: Instance, statType: StatType, source_id: string, newValue: number)
	local stats = entityStats[entity]
	if not stats then
		warn(`Attempted to update modifier for entity {entity.Name} who has no stats initialized`)
		return false
	end
	local stat = stats[statType]
	if not stat then
		warn(`Stat {statType} not found for entity {entity.Name}`)
		return false
	end
	local success = stat:updateModifier(source_id, newValue)
	if success then
		StatsMediator.invalidateStat(entity, statType)
		StatsManager.invalidateAllCaches(entity)
		if entity:IsA("Player") then
			sendStatDelta(
				entity,
				StatTypeUtil.DeltaTypes.MODIFIER_UPDATED,
				statType,
				{ source_id = source_id, value = newValue }
			)
		end
		return true
	end
	warn(`Modifier '{source_id}' not found in {entity.Name}'s {statType}`)
	return false
end

function StatsManager.hasModifier(entity: Instance, statType: StatType, source_id: string): boolean
	local stats = entityStats[entity]
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

function StatsManager.getStat(entity: Instance, statType: StatType): Types.StatInstance?
	local stats = entityStats[entity]
	if not stats then
		return nil
	end
	return stats[statType]
end

function StatsManager.getStatValue(entity: Instance, statType: StatType): number?
	local stats = entityStats[entity]
	if not stats then
		return nil
	end
	local stat = stats[statType]
	if not stat then
		return nil
	end
	return StatsMediator.resolve(entity, statType, function()
		return stat:getValue(stats)
	end, {
		context = "getStatValue",
		cacheKey = "value",
	})
end

function StatsManager.getAllStats(entity: Instance): PlayerStats?
	return entityStats[entity]
end

-- Convenience getters for pool stats (current vs max)
function StatsManager.getPoolCurrentValue(entity: Instance, poolName: PoolType): number?
	local stats = entityStats[entity]
	if not stats then
		return nil
	end
	local pool = (stats :: any)[poolName]
	if pool and pool.getCurrentValue then
		return pool:getCurrentValue()
	end
	return nil
end

function StatsManager.getPoolMaxValue(entity: Instance, poolName: PoolType): number?
	local stats = entityStats[entity]
	if not stats then
		return nil
	end
	local pool = (stats :: any)[poolName]
	if not pool or not pool.getValue then
		return nil
	end
	return StatsMediator.resolve(entity, poolName, function()
		return pool:getValue(stats)
	end, {
		context = "getPoolMaxValue",
		cacheKey = "max",
	})
end

function StatsManager.getPoolPercentage(entity: Instance, poolName: PoolType): number?
	local stats = entityStats[entity]
	if not stats then
		return nil
	end
	local pool = (stats :: any)[poolName]
	if pool and pool.getPercentage then
		return pool:getPercentage(stats)
	end
	return nil
end

function StatsManager.invalidateAllCaches(entity: Instance)
	local stats = entityStats[entity]
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
	StatsMediator.invalidateAll(entity)
end

function StatsManager.setProfilingEnabled(enabled: boolean)
	profilingEnabled = enabled
end

function StatsManager.resetStats(entity: Instance)
	if not entityStats[entity] then
		warn(`Attempted to reset stats for entity {entity.Name} who has no stats initialized`)
		return false
	end
	local stats = StatsConfig.createDefaultStats()
	entityStats[entity] = stats
	StatsMediator.attach(entity, stats)
	StatsMediator.invalidateAll(entity)
	if entity:IsA("Player") then
		sendFullSync(entity)
		print(`Reset stats for player: {entity.Name}`)
	else
		print(`Reset stats for entity: {entity:GetFullName()}`)
	end
	return true
end

function StatsManager.emitDelta(entity: Instance, deltaType: string, target: string, data: any)
	sendStatDelta(entity, deltaType, target, data)
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
	if not StatsManager.isRegistered(player) then
		StatsManager.register(player)
	end
	local stats = entityStats[player]
	if not stats then
		return nil
	end
	debugLog("Request full snapshot", player.Name)
	return StatTypeUtil.serializeStats(stats)
end)

-- Connect player events
Players.PlayerAdded:Connect(initializePlayerStats)
Players.PlayerRemoving:Connect(cleanupPlayerStats)

print("StatsManager initialized with custom networking")
return StatsManager