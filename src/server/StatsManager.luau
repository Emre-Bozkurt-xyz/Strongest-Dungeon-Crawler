--!strict
-- Server-side player stat management system
-- Handles all stat modifications and syncing to clients

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetRay = require(ReplicatedStorage.Packages.NetRay)
local StatsConfig = require(game.ReplicatedStorage.Shared.StatsConfig)
local Types = require(game.ReplicatedStorage.Shared.StatTypes)
local StatTypeUtil = require(ReplicatedStorage.Shared.StatTypeUtil)

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

local StatsManager = {}
local playerStats: { [Player]: PlayerStats } = {}

-- NetRay endpoints
local statsDelta = NetRay:RegisterEvent("StatsDelta")
local statsRequest = NetRay:RegisterRequestEvent("StatsRequest")

-- Helper: send a delta to a player
local function sendStatDelta(player: Player, deltaType: string, target: string, data: any)
	local delta: Delta = {
		system = "stats",
		type = deltaType,
		target = target,
		data = data,
		timestamp = tick(),
	}
	statsDelta:FireClient(player, delta)
end

-- Helper: send full sync
local function sendFullSync(player: Player)
	local stats = playerStats[player]
	if not stats then
		return
	end
	local serialized = StatTypeUtil.serializeStats(stats)
	local delta: Delta = {
		system = "stats",
		type = StatTypeUtil.DeltaTypes.FULL_SYNC,
		target = "ALL_DATA",
		data = serialized,
		timestamp = tick(),
	}
	statsDelta:FireClient(player, delta)
end

-- Initialize stats for a new player
local function initializePlayerStats(player: Player)
	playerStats[player] = StatsConfig.createDefaultStats()
	-- Allow client to request, but we can also push initial full sync
	sendFullSync(player)
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

	stat:setBaseValue(validatedValue)
	-- Send base value delta update
	sendStatDelta(player, StatTypeUtil.DeltaTypes.BASE_VALUE_CHANGED, statName, { baseValue = validatedValue })
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
		sendStatDelta(player, StatTypeUtil.DeltaTypes.CURRENT_VALUE_CHANGED, poolName, {
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
		sendStatDelta(player, StatTypeUtil.DeltaTypes.CURRENT_VALUE_CHANGED, poolName, {
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
	sendStatDelta(player, StatTypeUtil.DeltaTypes.RESERVATION_ADDED, poolName, reservation)
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
		sendStatDelta(player, StatTypeUtil.DeltaTypes.RESERVATION_REMOVED, poolName, { source_id = source_id })
	end
	return removed
end

function StatsManager.addModifier(player: Player, statType: StatType, modifier)
	if not playerStats[player] then
		warn(`Attempted to add modifier for player {player.Name} who has no stats initialized`)
		return false
	end
	local stat = playerStats[player][statType]
	stat:addModifier(modifier)
	StatsManager.invalidateAllCaches(player)
	sendStatDelta(player, StatTypeUtil.DeltaTypes.MODIFIER_ADDED, statType, modifier)
	return true
end

function StatsManager.removeModifier(player: Player, statType: StatType, source_id: string)
	if not playerStats[player] then
		warn(`Attempted to remove modifier for player {player.Name} who has no stats initialized`)
		return false
	end
	local stat = playerStats[player][statType]
	local removed = stat:removeModifier(source_id)
	if removed then
		StatsManager.invalidateAllCaches(player)
		sendStatDelta(player, StatTypeUtil.DeltaTypes.MODIFIER_REMOVED, statType, { source_id = source_id })
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
		StatsManager.invalidateAllCaches(player)
		sendStatDelta(
			player,
			StatTypeUtil.DeltaTypes.MODIFIER_UPDATED,
			statType,
			{ source_id = source_id, value = newValue }
		)
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

function StatsManager.getStat(player: Player, statType: StatType): Types.StatInstance?
	if not playerStats[player] then
		return nil
	end
	return playerStats[player][statType]
end

function StatsManager.getStatValue(player: Player, statType: StatType): number?
	if not playerStats[player] then
		return nil
	end
	return playerStats[player][statType]:getValue(playerStats[player])
end

function StatsManager.getAllStats(player: Player): PlayerStats?
	return playerStats[player]
end

function StatsManager.invalidateAllCaches(player: Player)
	local stats = playerStats[player]
	if not stats then
		return
	end
	for _, stat in pairs(stats) do
		if stat.invalidateCache then
			stat:invalidateCache()
		end
	end
end

function StatsManager.resetStats(player: Player)
	if not playerStats[player] then
		warn(`Attempted to reset stats for player {player.Name} who has no stats initialized`)
		return false
	end
	playerStats[player] = StatsConfig.createDefaultStats()
	sendFullSync(player)
	print(`Reset stats for player: {player.Name}`)
	return true
end

-- Request handler (C->S): return full serialized data
statsRequest:OnRequest(function(player, _requestData)
	if not playerStats[player] then
		initializePlayerStats(player)
	end
	return StatTypeUtil.serializeStats(playerStats[player])
end)

-- Connect player events
Players.PlayerAdded:Connect(initializePlayerStats)
Players.PlayerRemoving:Connect(cleanupPlayerStats)

print("StatsManager initialized with NetRay")
return StatsManager
