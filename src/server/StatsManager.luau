--!strict
-- Server-side player stat management system
-- Handles all stat modifications and syncing to clients

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Warp = require(game.ReplicatedStorage.Packages.warp)
local StatsConfig = require(game.ReplicatedStorage.Shared.StatsConfig)
local Types = require(game.ReplicatedStorage.Shared.StatTypes)
local StatTypeUtil = require(ReplicatedStorage.Shared.StatTypeUtil)
local NetworkManager = require(script.Parent.NetworkManager)

-- Import types from central location
type PlayerStats = Types.PlayerStats
type StatType = Types.StatType
type StaticStatType = Types.StaticStatType
type PoolType = Types.PoolType

local StatsManager = {}
local playerStats: { [Player]: PlayerStats } = {}

-- Initialize stats for a new player
local function initializePlayerStats(player: Player)
	playerStats[player] = StatsConfig.createDefaultStats()

	-- Send initial full sync via NetworkManager
	NetworkManager.sendFullSync(player, "stats", playerStats[player])

	print(`Initialized stats for player: {player.Name}`)
end

-- ========================================
-- HELPER FUNCTIONS FOR DELTAS
-- ========================================

-- Send a delta update to client via NetworkManager
local function sendStatDelta(player: Player, deltaType: string, target: string, data: any)
	local delta = NetworkManager.createDelta("stats", deltaType, target, data)
	NetworkManager.sendDelta(player, delta)
end

-- Handle LOCAL player stats requests
local function handleRemoteFunctionInvoke(_system: string, data: any): any
	print("TEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEST")
	local stats = {}
	for requestedStat in ipairs(data.requestedStats or {}) do
		local stat = playerStats[data.player][requestedStat]
		if stat then
			table.insert(stats, stat)
		else
			warn(`Stat {requestedStat} not found for player {data.player.Name}`)
		end
	end
	return stats
end

-- ========================================
-- BATCHING SYSTEM FOR SCALING OPERATIONS
-- ========================================

-- Enable batching mode to prevent individual client updates during scaling
function StatsManager.enableBatching(player: Player)
	NetworkManager.enableBatching(player, "stats")
end

-- Disable batching and send accumulated deltas
function StatsManager.disableBatching(player: Player)
	NetworkManager.disableBatching(player, "stats")
end

-- Clean up when player leaves
local function cleanupPlayerStats(player: Player)
	playerStats[player] = nil
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
	sendStatDelta(player, "base_value_changed", statName, { baseValue = validatedValue })

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
		sendStatDelta(player, "current_value_changed", poolName, {
			currentValue = pool:getCurrentValue(),
			maxValue = pool:getValue(playerStats[player]),
		})
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
		sendStatDelta(player, "current_value_changed", poolName, {
			currentValue = pool:getCurrentValue(),
			maxValue = pool:getValue(playerStats[player]),
		})
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
	sendStatDelta(player, "reservation_added", poolName, reservation)

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
		sendStatDelta(player, "reservation_removed", poolName, { source_id = source_id })
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
	sendStatDelta(player, "modifier_added", statType, modifier)

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
		sendStatDelta(player, "modifier_removed", statType, { source_id = source_id })
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
		sendStatDelta(player, "modifier_updated", statType, {
			source_id = source_id,
			value = newValue,
		})
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

	-- Send full sync for reset
	NetworkManager.sendFullSync(player, "stats", playerStats[player])

	print(`Reset stats for player: {player.Name}`)
	return true
end

-- Stats System Handler for NetworkManager
local statsHandler = {
	serialize = function(data: PlayerStats): any
		return StatTypeUtil.serializeStats(data)
	end,
	deserialize = function(data: any): PlayerStats
		return StatTypeUtil.deserializeStats(data)
	end,
	applyDelta = function(currentData: PlayerStats, delta): boolean
		return StatTypeUtil.applyDelta(currentData, delta)
	end,
}

-- Register stats system with NetworkManager
NetworkManager.registerSystem("stats", statsHandler)

-- Handle client requests for stats
local function handleStatsRequest(player: Player)
	if playerStats[player] then
		NetworkManager.sendFullSync(player, "stats", playerStats[player])
	else
		initializePlayerStats(player)
	end
end

-- Listen for stats requests via NetworkManager
local statsRequestSignal = Warp.Signal("statsFullSyncRequest")
statsRequestSignal:Connect(handleStatsRequest)

local statsSignal = Warp.Signal("statsSignal")
statsSignal:Connect(handleRemoteFunctionInvoke)

-- Connect player events
Players.PlayerAdded:Connect(initializePlayerStats)
Players.PlayerRemoving:Connect(cleanupPlayerStats)

print("StatsManager initialized with NetworkManager")
return StatsManager
