--!strict
-- Client-side stats display and handling (NetRay-based)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local NetRay = require(ReplicatedStorage.Packages.NetRay)
local StatTypeUtil = require(ReplicatedStorage.Shared.StatTypeUtil)
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)

-- Local state for stats
local currentStats: StatTypes.PlayerStats? = nil

-- NetRay endpoints
local statsEvent = NetRay:GetEvent("StatsDelta")
local statsRequest = NetRay:RegisterRequestEvent("StatsRequest")

-- Apply incoming deltas to local state
local function onStatsDelta(delta: any)
	-- If this is a full sync, (re)initialize state
	if delta and delta.type == StatTypeUtil.DeltaTypes.FULL_SYNC and delta.data then
		local ok, deserialized = pcall(function()
			return StatTypeUtil.deserializeStats(delta.data)
		end)
		if ok then
			currentStats = deserialized
		else
			warn("StatsClient: Failed to deserialize full_sync:", deserialized)
		end
		return
	end

	if not currentStats then
		-- If no state yet, request a full sync and skip applying incremental deltas
		-- The server may also push a full_sync on join
		return
	end

	local success = pcall(function()
		StatTypeUtil.applyDelta(currentStats :: StatTypes.PlayerStats, delta)
	end)

	if not success then
		warn("StatsClient: Failed to apply delta")
	end
end

-- Request fresh stats data from server
local function requestStats()
	statsRequest
		:Request({})
		:andThen(function(serialized)
			local ok, deserialized = pcall(function()
				return StatTypeUtil.deserializeStats(serialized)
			end)
			if ok then
				currentStats = deserialized
			else
				warn("StatsClient: Failed to deserialize stats:", deserialized)
			end
		end)
		:catch(function(err)
			warn("StatsClient: Failed to request stats:", err)
		end)
end

-- Initialize listeners once
if statsEvent then
	statsEvent:OnEvent(onStatsDelta)
end

-- Public API
local StatsClient = {}

function StatsClient.getCurrentStats(): StatTypes.PlayerStats?
	return currentStats
end

function StatsClient.getFormattedStats(): StatTypes.PlayerStats?
	if not currentStats then
		-- Trigger a request and return nil for now
		StatsClient.requestStatsUpdate()
		return nil
	end
	return currentStats
end

function StatsClient.requestStatsUpdate()
	requestStats()
end

-- Initial request after character loads
local function onCharacterAdded(_char: Model)
	-- slight delay to ensure server has initialized
	task.delay(0.2, requestStats)
end

if Players.LocalPlayer.Character then
	onCharacterAdded(Players.LocalPlayer.Character)
end
Players.LocalPlayer.CharacterAdded:Connect(onCharacterAdded)

return StatsClient
