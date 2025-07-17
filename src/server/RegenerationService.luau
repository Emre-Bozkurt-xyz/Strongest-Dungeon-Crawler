--!strict
-- Regeneration Service - Handles automatic regeneration for pool stats
-- Ticks 30 times per second and applies smooth regeneration based on regen stats

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local StatsManager = require(script.Parent.StatsManager)
local Types = require(game.ReplicatedStorage.Shared.StatTypes)
local StatTypeUtil = require(game.ReplicatedStorage.Shared.StatTypeUtil)
local Warp = require(game.ReplicatedStorage.Packages.warp)

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

-- Warp event for sending delta updates
local statsDeltaEvent = Warp.Server("StatsDelta") -- For efficient regeneration updates

-- Pool stats and their associated regeneration stats
local REGEN_MAPPING = {
	[Types.PoolStats.Health] = Types.StaticStats.HealthRegeneration,
	[Types.PoolStats.Mana] = Types.StaticStats.ManaRegeneration,
	[Types.PoolStats.Stamina] = Types.StaticStats.StaminaRegeneration,
}

-- Apply regeneration to a single player
local function regeneratePlayer(player: Player, deltaTime: number)
	-- Get all player stats
	local stats = StatsManager.getAllStats(player)
	if not stats then
		return false -- Player not initialized yet
	end

	local anyRegenApplied = false

	-- Process each pool stat
	for poolType, regenStatType in pairs(REGEN_MAPPING) do
		local pool = stats[poolType]
		local regenStat = stats[regenStatType]

		if pool and regenStat then
			-- Get regeneration rate (per second)
			local regenPerSecond = regenStat:getValue(stats)

			if regenPerSecond > 0 then
				-- Calculate regeneration for this tick (smooth over the tick interval)
				local regenThisTick = regenPerSecond * deltaTime

				-- Add to the pool directly (without triggering individual client updates)
				local actualRegen = pool:addToCurrentValue(regenThisTick, stats)

				if actualRegen > 0 then
					anyRegenApplied = true
				end
			end
		end
	end

	return anyRegenApplied
end

-- Main regeneration tick function
local function onRegenerationTick()
	local currentTime = tick()
	local deltaTime = TICK_INTERVAL -- Fixed delta time for consistent regeneration

	local playersWithUpdates = {}

	-- Process all connected players
	for _, player in pairs(Players:GetPlayers()) do
		local hadRegen = regeneratePlayer(player, deltaTime)
		if hadRegen then
			table.insert(playersWithUpdates, player)
		end
	end

	-- Send batched updates only every UPDATE_INTERVAL to reduce network spam
	if currentTime - lastUpdateTime >= UPDATE_INTERVAL and #playersWithUpdates > 0 then
		for _, player in pairs(playersWithUpdates) do
			local stats = StatsManager.getAllStats(player)
			if stats then
				-- Create delta updates for each pool stat that regenerated
				local deltas = {}

				for poolType, _ in pairs(REGEN_MAPPING) do
					local pool = stats[poolType]
					if pool then
						-- Send current value delta for this pool
						local delta =
							StatTypeUtil.createCurrentValueDelta(poolType, pool:getCurrentValue(), pool:getValue(stats))
						table.insert(deltas, delta)
					end
				end

				-- Send batched deltas instead of full stats
				if #deltas > 0 then
					local batchedUpdate = StatTypeUtil.createBatchedDeltas(deltas)
					statsDeltaEvent:Fire(true, player, batchedUpdate)
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
	regeneratePlayer(player, actualDeltaTime)
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

return RegenerationService
