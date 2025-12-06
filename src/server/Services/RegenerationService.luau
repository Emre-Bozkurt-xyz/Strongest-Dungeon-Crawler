-- Regeneration Service - Handles automatic regeneration for pool stats (players + NPCs)
-- Ticks 30 times per second and applies smooth regeneration based on regen stats

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = game:GetService("ServerScriptService").Server

local StatsManager = require(Server.Stats.StatsManager)
local Types = require(ReplicatedStorage.Shared.StatTypes)
local StatTypeUtil = require(ReplicatedStorage.Shared.StatTypeUtil)
local Registrar = require(Server.Services.Registrar)

local RegenerationService = {}

-- Configuration
local TICK_RATE = 30 -- 30 ticks per second for smooth regeneration
local TICK_INTERVAL = 1 / TICK_RATE -- ~0.033 seconds per tick
local UPDATE_RATE = 2 -- Send updates to client only 2 times per second
local UPDATE_INTERVAL = 1 / UPDATE_RATE -- 0.5 seconds between client updates

-- Track active players and connection
local activeConnection: RBXScriptConnection? = nil
local isRunning = false
local lastUpdateTime = 0
local lastSentValues = {} -- Track the last values sent to each player for each pool

-- Pool stats and their associated regeneration stats
local REGEN_MAPPING = {
	[Types.PoolStats.Health] = Types.StaticStats.HealthRegeneration,
	[Types.PoolStats.Mana] = Types.StaticStats.ManaRegeneration,
	[Types.PoolStats.Stamina] = Types.StaticStats.StaminaRegeneration,
}

-- Apply regeneration to a single entity
local function regenerateEntity(entityId: string, deltaTime: number)
	local stats = StatsManager.getAllStats(entityId)
	if not stats then
		return {}
	end

	local changedPools = {}

	-- Process each pool stat
	for poolType, regenStatType in pairs(REGEN_MAPPING) do
		local pool = stats[poolType]
		local regenStat = stats[regenStatType]

		if pool and regenStat then
			-- Get regeneration rate (per second)
			local regenPerSecond = StatsManager.getStatValue(entityId, regenStatType, {
				event = "regenerationStatQuery",
				metadata = {
					entity = entityId,
					pool = poolType,
					stat = regenStatType,
				},
			}) or 0

			if regenPerSecond > 0 then
				-- Calculate regeneration for this tick (smooth over the tick interval)
				local regenThisTick = regenPerSecond * deltaTime

				-- Add to the pool directly (without triggering individual client updates)
				local actualRegen = pool:addToCurrentValue(regenThisTick, stats)

				if actualRegen > 0 then
					table.insert(changedPools, poolType)
				end
			end
		end
	end

	return changedPools
end

-- Main regeneration tick function
local tickCount = 0
local function onRegenerationTick()
	local currentTime = tick()
	local deltaTime = TICK_INTERVAL -- Fixed delta time for consistent regeneration
	tickCount = tickCount + 1

	for entityId, _ in pairs(Registrar.getAllEntities()) do
		regenerateEntity(entityId, deltaTime)
	end

	-- Send updates only every UPDATE_INTERVAL to reduce network spam
	if currentTime - lastUpdateTime >= UPDATE_INTERVAL then
		local deltasSent = 0
		for _, player in pairs(Players:GetPlayers()) do
			local stats = StatsManager.getAllStats(player)
			if stats then
				-- Initialize tracking for this player if needed
				if not lastSentValues[player] then
					lastSentValues[player] = {}
				end

				for poolType, _ in pairs(REGEN_MAPPING) do
					local pool = stats[poolType]
					if pool then
						local currentValue = StatsManager.getPoolCurrentValue(player, poolType, {
							event = "regenerationResourceQuery",
							metadata = {
								entity = player,
								pool = poolType,
								stage = "sync",
							},
						}) or pool:getCurrentValue()
						local lastValue = lastSentValues[player][poolType]
						local maxValue = StatsManager.getPoolMaxValue(player, poolType, {
							event = "regenerationResourceMax",
							metadata = {
								entity = player,
								pool = poolType,
								stage = "sync",
							},
						}) or pool:getValue(stats)

						-- Only send delta if the value actually changed
						if not lastValue or math.abs(currentValue - lastValue) > 0.01 then
							StatsManager.emitDelta(player, StatTypeUtil.DeltaTypes.CURRENT_VALUE_CHANGED, poolType, {
								currentValue = currentValue,
								maxValue = maxValue,
							})
							lastSentValues[player][poolType] = currentValue
							deltasSent = deltasSent + 1
						end
					end
				end
			end
		end
		lastUpdateTime = currentTime
	end
end

-- Start the regeneration service
function RegenerationService.start()
	if isRunning then
		warn("RegenerationService is already running")
		return
	end

	print("Starting RegenerationService with", TICK_RATE, "ticks per second")

	-- Create heartbeat connection with custom timing
	local lastTick = tick()
	activeConnection = RunService.Heartbeat:Connect(function()
		local currentTime = tick()
		local timeSinceLastTick = currentTime - lastTick

		-- Only tick if enough time has passed (maintains consistent 30 FPS)
		if timeSinceLastTick >= TICK_INTERVAL then
			onRegenerationTick()
			lastTick = currentTime
		end
	end)

	isRunning = true
	print("RegenerationService started successfully")
end

-- Stop the regeneration service
function RegenerationService.stop()
	if not isRunning then
		warn("RegenerationService is not running")
		return
	end

	if activeConnection then
		activeConnection:Disconnect()
		activeConnection = nil
	end

	isRunning = false
	print("RegenerationService stopped")
end

-- Check if the service is running
function RegenerationService.isRunning(): boolean
	return isRunning
end

-- Get current tick rate
function RegenerationService.getTickRate(): number
	return TICK_RATE
end

-- Update tick rate (requires restart to take effect)
function RegenerationService.setTickRate(newTickRate: number)
	if newTickRate <= 0 or newTickRate > 60 then
		warn("Invalid tick rate:", newTickRate, "- must be between 1 and 60")
		return false
	end

	local wasRunning = isRunning

	if wasRunning then
		RegenerationService.stop()
	end

	TICK_RATE = newTickRate
	TICK_INTERVAL = 1 / TICK_RATE

	if wasRunning then
		RegenerationService.start()
	end

	print("Regeneration tick rate updated to", TICK_RATE, "ticks per second")
	return true
end

-- Manual regeneration for a specific player (useful for testing)
function RegenerationService.regeneratePlayerManually(player: Player, deltaTime: number?)
	local actualDeltaTime = deltaTime or TICK_INTERVAL

	local playerId = Registrar.getPlayerId(player)

	local changedPools = regenerateEntity(playerId, actualDeltaTime)
	return changedPools
end

-- Optional: generic manual hook (can be used for NPCs)
function RegenerationService.regenerateEntityManually(entityId: string, deltaTime: number?)
	local actualDeltaTime = deltaTime or TICK_INTERVAL
	local changedPools = regenerateEntity(entityId, actualDeltaTime)
	return changedPools
end

-- Get regeneration info for debugging
function RegenerationService.getDebugInfo(): { [string]: any }
	return {
		isRunning = isRunning,
		tickRate = TICK_RATE,
		tickInterval = TICK_INTERVAL,
		playerCount = #Players:GetPlayers(),
		regenMapping = REGEN_MAPPING,
	}
end

-- Clean up tracking data when players leave
Players.PlayerRemoving:Connect(function(player)
	if lastSentValues[player] then
		lastSentValues[player] = nil
	end
end)

return RegenerationService
