--!strict
-- Server-side player stat management system
-- Handles all stat modifications and syncing to clients

local Players = game:GetService("Players")

local Warp = require(game.ReplicatedStorage.Packages.warp)
local StatsConfig = require(game.ReplicatedStorage.Shared.StatsConfig)

type StatType = StatsConfig.StatType
type StatData = StatsConfig.StatData
type PlayerStats = StatsConfig.PlayerStats
type StatModifier = StatsConfig.StatModifier

local StatsManager = {}
local playerStats: { [Player]: PlayerStats } = {}

-- Warp events for networking
local statsUpdateEvent = Warp.Server("StatsUpdate")
local statsRequestEvent = Warp.Server("StatsRequest")

-- Initialize stats for a new player
local function initializePlayerStats(player: Player)
	playerStats[player] = StatsConfig.createDefaultStats()

	-- Send initial stats to the player
	statsUpdateEvent:Fire(true, player, playerStats[player])

	print(`Initialized stats for player: {player.Name}`)
end

-- Clean up when player leaves
local function cleanupPlayerStats(player: Player)
	playerStats[player] = nil
	print(`Cleaned up stats for player: {player.Name}`)
end

-- Update a player's stat and notify client
function StatsManager.setBaseStat(player: Player, statType: StatType, newValue: number)
	if not playerStats[player] then
		warn(`Attempted to set stat for player {player.Name} who has no stats initialized`)
		return false
	end

	local validatedValue = StatsConfig.validateStatValue(newValue)
	local stat = playerStats[player][statType]

	-- Recalculate current value
	stat.base = validatedValue

	-- Notify the client of the change
	statsUpdateEvent:Fire(true, player, playerStats[player])

	print(
		`Updated {player.Name}'s {statType} to {stat.base + StatsManager.getAllModifiers(playerStats[player], statType)} (base: {stat.base}, modifiers: {StatsManager.getAllModifiers(
			playerStats[player],
			statType
		)})`
	)
	return true
end

function StatsManager.getAllModifiers(stats: PlayerStats, statType: StatType): number
	local total = 0
	for _, modifier in pairs(stats[statType].modifiers) do
		if modifier.type == "flat" then
			total += modifier.value
		end
	end
	return total
end

-- Get a player's current stat value
function StatsManager.getStat(player: Player, statType: StatType): StatData?
	if not playerStats[player] then
		return nil
	end

	return playerStats[player][statType]
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
	statsUpdateEvent:Fire(true, player, playerStats[player])

	print(`Reset stats for player: {player.Name}`)
	return true
end

-- Handle client requests for stats
local function handleStatsRequest(player: Player)
	if playerStats[player] then
		statsUpdateEvent:Fire(true, player, playerStats[player])
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
