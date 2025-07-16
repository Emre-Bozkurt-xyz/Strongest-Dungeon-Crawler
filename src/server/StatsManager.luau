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

-- Warp events for networking
local statsUpdateEvent = Warp.Server("StatsUpdate")
local statsRequestEvent = Warp.Server("StatsRequest")

-- Initialize stats for a new player
local function initializePlayerStats(player: Player)
	playerStats[player] = StatsConfig.createDefaultStats()

	-- Send initial stats to the player
	statsUpdateEvent:Fire(true, player, StatTypeUtil.serializeStats(playerStats[player]))

	print(`Initialized stats for player: {player.Name}`)
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

	-- Notify the client of the change
	statsUpdateEvent:Fire(true, player, StatTypeUtil.serializeStats(playerStats[player]))

	print(`Updated {player.Name}'s {statName} base to {validatedValue}`)
	return true
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
		-- Notify the client of the change
		statsUpdateEvent:Fire(true, player, StatTypeUtil.serializeStats(playerStats[player]))
		print(`Removed {amount} from {player.Name}'s {poolName}`)
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

	-- Notify the client of the change
	statsUpdateEvent:Fire(true, player, StatTypeUtil.serializeStats(playerStats[player]))

	print(`Added reservation to {player.Name}'s {poolName}: {reservation.description}`)
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
		-- Notify the client of the change
		statsUpdateEvent:Fire(true, player, StatTypeUtil.serializeStats(playerStats[player]))
		print(`Removed reservation from {player.Name}'s {poolName}: {source_id}`)
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

	-- Notify the client of the change
	statsUpdateEvent:Fire(true, player, StatTypeUtil.serializeStats(playerStats[player]))

	print(`Added modifier '{modifier.source_id}' to {player.Name}'s {statType}`)
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
		-- Notify the client of the change
		statsUpdateEvent:Fire(true, player, StatTypeUtil.serializeStats(playerStats[player]))
		print(`Removed modifier '{source_id}' from {player.Name}'s {statType}`)
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
		statsUpdateEvent:Fire(true, player, StatTypeUtil.serializeStats(playerStats[player]))
		print(`Updated modifier '{source_id}' for {player.Name}'s {statType}`)
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

-- Reset all stats to default values
function StatsManager.resetStats(player: Player)
	if not playerStats[player] then
		warn(`Attempted to reset stats for player {player.Name} who has no stats initialized`)
		return false
	end

	playerStats[player] = StatsConfig.createDefaultStats()
	statsUpdateEvent:Fire(true, player, StatTypeUtil.serializeStats(playerStats[player]))

	print(`Reset stats for player: {player.Name}`)
	return true
end

-- Handle client requests for stats
local function handleStatsRequest(player: Player)
	if playerStats[player] then
		statsUpdateEvent:Fire(true, player, StatTypeUtil.serializeStats(playerStats[player]))
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
