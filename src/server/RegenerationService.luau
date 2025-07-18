-- Regeneration Service - Handles automatic regeneration for pool stats
-- Ticks 30 times per second and applies smooth regeneration based on regen stats

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local StatsManager = require(script.Parent.StatsManager)
local NetworkManager = require(script.Parent.NetworkManager)
local Types = require(game.ReplicatedStorage.Shared.StatTypes)

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

-- Apply regeneration to a single player
local function regeneratePlayer(player: Player, deltaTime: number)
	-- Get all player stats
	local stats = StatsManager.getAllStats(player)
	if not stats then
		return {} -- Player not initialized yet
	end

	local changedPools = {}

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
					table.insert(changedPools, poolType)
				end
			end
		end
	end

	return changedPools
end

-- Main regeneration tick function
local function onRegenerationTick()
	local currentTime = tick()
	local deltaTime = TICK_INTERVAL -- Fixed delta time for consistent regeneration

	-- Process all connected players and apply regeneration
	for _, player in pairs(Players:GetPlayers()) do
		regeneratePlayer(player, deltaTime)
	end

	-- Send batched updates only every UPDATE_INTERVAL to reduce network spam
	if currentTime - lastUpdateTime >= UPDATE_INTERVAL then
		for _, player in pairs(Players:GetPlayers()) do
			local stats = StatsManager.getAllStats(player)
			if stats then
				-- Initialize tracking for this player if needed
				if not lastSentValues[player] then
					lastSentValues[player] = {}
				end

				-- Check which pools have actually changed since last update
				local deltas = {}

				for poolType, _ in pairs(REGEN_MAPPING) do
					local pool = stats[poolType]
					if pool then
						local currentValue = pool:getCurrentValue()
						local lastValue = lastSentValues[player][poolType]

						-- Only send delta if the value actually changed
						if not lastValue or math.abs(currentValue - lastValue) > 0.01 then -- Small threshold for floating point precision
							local delta = NetworkManager.createDelta("stats", "current_value_changed", poolType, {
								currentValue = currentValue,
								maxValue = pool:getValue(stats), -- Include max for UI percentage calculations
							})
							table.insert(deltas, delta)

							-- Update the last sent value
							lastSentValues[player][poolType] = currentValue
						end
					end
				end

				-- Send batched deltas instead of full stats
				if #deltas > 0 then
					-- Enable batching for efficient regeneration updates
					StatsManager.enableBatching(player)

					-- Apply all the regeneration deltas
					for _, delta in ipairs(deltas) do
						-- The delta contains the updated current value, just send it via NetworkManager
						NetworkManager.sendDelta(player, delta)
					end

					-- Disable batching to send the batch
					StatsManager.disableBatching(player)
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
	local changedPools = regeneratePlayer(player, actualDeltaTime)
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
