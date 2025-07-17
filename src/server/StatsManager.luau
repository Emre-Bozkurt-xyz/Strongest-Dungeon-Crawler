--!strict
-- Server-side player stat management system
-- Handles all stat modifications and syncing to clients

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Warp = require(game.ReplicatedStorage.Packages.warp)
local StatsConfig = require(game.ReplicatedStorage.Shared.StatsConfig)
local Types = require(game.ReplicatedStorage.Shared.StatTypes)
local StatTypeUtil = require(ReplicatedStorage.Shared.StatTypeUtil)

-- Import types from central location
type PlayerStats = Types.PlayerStats
type StatType = Types.StatType
type StaticStatType = Types.StaticStatType
type PoolType = Types.PoolType

local StatsManager = {}
local playerStats: { [Player]: PlayerStats } = {}

-- Batching system to prevent excessive client updates during scaling
local batchingEnabled: { [Player]: boolean } = {}

-- Store pending deltas for batching
local pendingDeltas: { [Player]: { any } } = {}

-- Warp events for networking
local statsRequestEvent = Warp.Server("StatsRequest")
local statsDeltaEvent = Warp.Server("StatsDelta") -- Primary communication method

-- Initialize stats for a new player
local function initializePlayerStats(player: Player)
	playerStats[player] = StatsConfig.createDefaultStats()

	-- Send initial full sync via delta system
	local fullSyncDelta = StatTypeUtil.createDelta(
		StatTypeUtil.DeltaTypes.FULL_SYNC,
		"ALL_STATS",
		StatTypeUtil.serializeStats(playerStats[player])
	)
	statsDeltaEvent:Fire(true, player, fullSyncDelta)

	print(`Initialized stats for player: {player.Name}`)
end

-- ========================================
-- DELTA UPDATE FUNCTIONS
-- ========================================

-- Add a delta to pending batch (used during batching mode)
local function addToPendingDeltas(player: Player, delta: any)
	if not pendingDeltas[player] then
		pendingDeltas[player] = {}
	end
	table.insert(pendingDeltas[player], delta)
end

-- Send a single delta update to client
local function sendDelta(player: Player, delta: any)
	if not batchingEnabled[player] then
		statsDeltaEvent:Fire(true, player, delta)
	else
		-- If batching is enabled, add to pending deltas
		addToPendingDeltas(player, delta)
	end
end

-- Send multiple deltas as a batch
local function sendBatchedDeltas(player: Player, deltas: { any })
	if #deltas > 0 then
		local batchedUpdate = StatTypeUtil.createBatchedDeltas(deltas)
		statsDeltaEvent:Fire(true, player, batchedUpdate)
	end
end

-- ========================================
-- BATCHING SYSTEM FOR SCALING OPERATIONS
-- ========================================

-- Enable batching mode to prevent individual client updates during scaling
function StatsManager.enableBatching(player: Player)
	batchingEnabled[player] = true
	pendingDeltas[player] = {} -- Clear any existing pending deltas
end

-- Disable batching and send accumulated deltas
function StatsManager.disableBatching(player: Player)
	batchingEnabled[player] = false

	-- Send accumulated deltas as a batch
	if pendingDeltas[player] and #pendingDeltas[player] > 0 then
		sendBatchedDeltas(player, pendingDeltas[player])
		pendingDeltas[player] = {} -- Clear after sending
	end
end

-- Clean up when player leaves
local function cleanupPlayerStats(player: Player)
	playerStats[player] = nil
	batchingEnabled[player] = nil
	pendingDeltas[player] = nil
	print(`Cleaned up stats for player: {player.Name}`)
end

-- Set base value for stats or pools
function StatsManager.setBaseStat(player: Player, statName: StatType, newValue: number)
	if not playerStats[player] then
		warn(`Attempted to set stat for player {player.Name} who has no stats initialized`)
		return false
	end

	local validatedValue = StatsConfig.validateStatValue(newValue)
	local stat = (playerStats[player] :: any)[statName]

	if not stat then
		warn(`Stat {statName} not found for player {player.Name}`)
		return false
	end

	-- Set the base value
	stat:setBaseValue(validatedValue)

	-- Send base value delta update
	local delta = StatTypeUtil.createBaseValueDelta(statName, validatedValue)
	sendDelta(player, delta)

	return true
end

function StatsManager.addToPool(player: Player, poolName: PoolType, amount: number): boolean
	if not playerStats[player] then
		warn(`Attempted to add to pool for player {player.Name} who has no stats initialized`)
		return false
	end

	local pool = (playerStats[player] :: any)[poolName]
	if not pool or not StatTypeUtil.isPoolStat(pool) then
		warn(`Pool {poolName} not found for player {player.Name}`)
		return false
	end

	local added = pool:addToCurrentValue(amount)

	if added then
		-- Send current value delta update
		local delta =
			StatTypeUtil.createCurrentValueDelta(poolName, pool:getCurrentValue(), pool:getValue(playerStats[player]))
		sendDelta(player, delta)
	end

	return added
end

function StatsManager.removeFromPool(player: Player, poolName: PoolType, amount: number)
	if not playerStats[player] then
		warn(`Attempted to remove from pool for player {player.Name} who has no stats initialized`)
		return false
	end

	local pool = (playerStats[player] :: any)[poolName]
	if not pool or not StatTypeUtil.isPoolStat(pool) then
		warn(`Pool {poolName} not found for player {player.Name}`)
		return false
	end

	local removed = pool:removeFromCurrentValue(amount)

	if removed then
		-- Send current value delta update
		local delta =
			StatTypeUtil.createCurrentValueDelta(poolName, pool:getCurrentValue(), pool:getValue(playerStats[player]))
		sendDelta(player, delta)
	end

	return removed
end

function StatsManager.addReservation(player: Player, poolName: PoolType, reservation)
	if not playerStats[player] then
		return false
	end

	local pool = (playerStats[player] :: any)[poolName]
	if not pool or not pool.addReservation then
		return false
	end

	pool:addReservation(reservation)

	-- Send reservation added delta
	local delta = StatTypeUtil.createDelta(StatTypeUtil.DeltaTypes.RESERVATION_ADDED, poolName, reservation)
	sendDelta(player, delta)

	return true
end

function StatsManager.removeReservation(player: Player, poolName: PoolType, source_id: string)
	if not playerStats[player] then
		return false
	end

	local pool = (playerStats[player] :: any)[poolName]
	if not pool or not pool.removeReservation then
		return false
	end

	local removed = pool:removeReservation(source_id)

	if removed then
		-- Send reservation removed delta
		local delta =
			StatTypeUtil.createDelta(StatTypeUtil.DeltaTypes.RESERVATION_REMOVED, poolName, { source_id = source_id })
		sendDelta(player, delta)
	end

	return removed
end

-- Add a modifier to a player's stat
function StatsManager.addModifier(player: Player, statType: StatType, modifier)
	if not playerStats[player] then
		warn(`Attempted to add modifier for player {player.Name} who has no stats initialized`)
		return false
	end

	local stat = playerStats[player][statType]
	stat:addModifier(modifier)

	-- Invalidate caches for all stats since modifiers can have cross-dependencies
	StatsManager.invalidateAllCaches(player)

	-- Send delta update instead of full stats
	local delta = StatTypeUtil.createModifierDelta(StatTypeUtil.DeltaTypes.MODIFIER_ADDED, statType, modifier)
	sendDelta(player, delta)

	return true
end

-- Remove a modifier from a player's stat
function StatsManager.removeModifier(player: Player, statType: StatType, source_id: string)
	if not playerStats[player] then
		warn(`Attempted to remove modifier for player {player.Name} who has no stats initialized`)
		return false
	end

	local stat = playerStats[player][statType]
	local removed = stat:removeModifier(source_id)

	if removed then
		-- Invalidate caches for all stats since modifiers can have cross-dependencies
		StatsManager.invalidateAllCaches(player)

		-- Send delta update instead of full stats
		local delta = StatTypeUtil.createDelta(StatTypeUtil.DeltaTypes.MODIFIER_REMOVED, statType, {
			source_id = source_id,
		})
		sendDelta(player, delta)
	end

	return removed
end

function StatsManager.updateModifier(player: Player, statType: StatType, source_id: string, newValue: number)
	if not playerStats[player] then
		warn(`Attempted to update modifier for player {player.Name} who has no stats initialized`)
		return false
	end

	local stat = playerStats[player][statType]
	if not stat then
		warn(`Stat {statType} not found for player {player.Name}`)
		return false
	end

	local success = stat:updateModifier(source_id, newValue)
	if success then
		-- Invalidate caches for all stats since modifiers can have cross-dependencies
		StatsManager.invalidateAllCaches(player)

		-- Send modifier updated delta
		local delta = StatTypeUtil.createDelta(StatTypeUtil.DeltaTypes.MODIFIER_UPDATED, statType, {
			source_id = source_id,
			value = newValue,
		})
		sendDelta(player, delta)
		return true
	end

	warn(`Modifier '{source_id}' not found in {player.Name}'s {statType}`)
	return false
end

function StatsManager.hasModifier(player: Player, statType: StatType, source_id: string): boolean
	if not playerStats[player] then
		return false
	end

	local stat = playerStats[player][statType]
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

-- Get a player's stat object
function StatsManager.getStat(player: Player, statType: StatType): Types.StatInstance?
	if not playerStats[player] then
		return nil
	end

	return playerStats[player][statType]
end

-- Get a player's current stat value
function StatsManager.getStatValue(player: Player, statType: StatType): number?
	if not playerStats[player] then
		return nil
	end

	return playerStats[player][statType]:getValue(playerStats[player])
end

-- Get all stats for a player
function StatsManager.getAllStats(player: Player): PlayerStats?
	return playerStats[player]
end

-- Invalidate all caches for a player (useful when stats have cross-dependencies)
function StatsManager.invalidateAllCaches(player: Player)
	local stats = playerStats[player]
	if not stats then
		return
	end

	-- Invalidate cache for all stats
	for _, stat in pairs(stats) do
		if stat.invalidateCache then
			stat:invalidateCache()
		end
	end
end

-- Reset all stats to default values
function StatsManager.resetStats(player: Player)
	if not playerStats[player] then
		warn(`Attempted to reset stats for player {player.Name} who has no stats initialized`)
		return false
	end

	playerStats[player] = StatsConfig.createDefaultStats()

	-- Send full sync delta for reset
	local fullSyncDelta = StatTypeUtil.createDelta(
		StatTypeUtil.DeltaTypes.FULL_SYNC,
		"ALL_STATS",
		StatTypeUtil.serializeStats(playerStats[player])
	)
	statsDeltaEvent:Fire(true, player, fullSyncDelta)

	print(`Reset stats for player: {player.Name}`)
	return true
end

-- Handle client requests for stats
local function handleStatsRequest(player: Player)
	if playerStats[player] then
		-- Send full sync delta for stat request
		local fullSyncDelta = StatTypeUtil.createDelta(
			StatTypeUtil.DeltaTypes.FULL_SYNC,
			"ALL_STATS",
			StatTypeUtil.serializeStats(playerStats[player])
		)
		statsDeltaEvent:Fire(true, player, fullSyncDelta)
	else
		initializePlayerStats(player)
	end
end

-- Connect events
statsRequestEvent:Connect(handleStatsRequest)

-- Connect player events
Players.PlayerAdded:Connect(initializePlayerStats)
Players.PlayerRemoving:Connect(cleanupPlayerStats)

print("StatsManager initialized")
return StatsManager
