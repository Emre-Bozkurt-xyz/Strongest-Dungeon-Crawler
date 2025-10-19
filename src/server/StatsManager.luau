--!strict
-- Server-side stat management system for players and NPCs
-- Handles all stat modifications and syncing to clients (players only receive dispatcher deltas)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Networking = require(ReplicatedStorage.Shared.Networking)
local StatsConfig = require(game.ServerScriptService.Server.StatsConfig)
local Types = require(game.ReplicatedStorage.Shared.StatTypes)
local StatTypeUtil = require(ReplicatedStorage.Shared.StatTypeUtil)

local DEBUG = false

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

-- Dispatcher channel wiring
local STATS_CHANNEL_NAME = "Stats"
local dispatcher = Networking.server()
local dispatcherAny = dispatcher :: any
dispatcherAny:_ensureChannel(STATS_CHANNEL_NAME)

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
	dispatcherAny:emit("StatsDelta", delta, {
		targets = player,
	})
end

function StatsManager.isRegistered(entity: Instance): boolean
	return entityStats[entity] ~= nil
end

function StatsManager.register(entity: Instance, options: RegisterOptions?): PlayerStats
	local existing = entityStats[entity]
	if existing then
		if options and options.configure then
			options.configure(existing)
		end
		if entity:IsA("Player") and not (options and options.skipSync) then
			sendFullSync(entity)
		end
		return existing
	end

	local stats = if options and options.stats then options.stats else StatsConfig.createDefaultStats()
	entityStats[entity] = stats

	if options and options.configure then
		options.configure(stats)
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
	if removed and entity:IsA("Player") then
		sendStatDelta(entity, StatTypeUtil.DeltaTypes.RESERVATION_REMOVED, poolName, { source_id = source_id })
	end
	return removed
end

function StatsManager.addModifier(entity: Instance, statType: StatType, modifier)
	local stats = entityStats[entity]
	if not stats then
		warn(`Attempted to add modifier for entity {entity.Name} who has no stats initialized`)
		return false
	end
	local stat = stats[statType]
	stat:addModifier(modifier)
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
	return stats[statType]:getValue(stats)
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
	if pool and pool.getValue then
		return pool:getValue(stats)
	end
	return nil
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
	for _, stat in pairs(stats) do
		if stat.invalidateCache then
			stat:invalidateCache()
		end
	end
end

function StatsManager.resetStats(entity: Instance)
	if not entityStats[entity] then
		warn(`Attempted to reset stats for entity {entity.Name} who has no stats initialized`)
		return false
	end
	entityStats[entity] = StatsConfig.createDefaultStats()
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
