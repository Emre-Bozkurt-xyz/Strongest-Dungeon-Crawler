--!strict
-- Client-side stats display and handling (dispatcher-based)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Networking = require(ReplicatedStorage.Shared.Networking)
local StatTypeUtil = require(ReplicatedStorage.Shared.StatTypeUtil)
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)

local DEBUG = false

local function debugLog(...)
	if DEBUG then
		print("[StatsClient]", ...)
	end
end

-- Local state for stats
local currentStats: StatTypes.PlayerStats? = nil
local changeSignal = Instance.new("BindableEvent")

type ChangeContext = {
	kind: "snapshot" | "delta",
	delta: any?,
}

local function notifyChange(context: ChangeContext)
	if not currentStats then
		return
	end
	changeSignal:Fire(currentStats, context)
end

local dispatcher = Networking.client()

-- Apply incoming deltas to local state
local function requestStats()
	local ok, serializedOrError = pcall(function()
		return (dispatcher :: any):request("StatsRequest", {})
	end)
	if not ok then
		warn("StatsClient: Failed to request stats:", serializedOrError)
		return
	end
	if serializedOrError == nil then
		warn("StatsClient: Received nil stats payload")
		return
	end

	local okDeserialize, deserialized = pcall(function()
		return StatTypeUtil.deserializeStats(serializedOrError)
	end)
	if okDeserialize then
		currentStats = deserialized
		debugLog("Applied snapshot from request", serializedOrError)
		notifyChange({ kind = "snapshot", delta = nil })
	else
		warn("StatsClient: Failed to deserialize stats:", deserialized)
	end
end

local function onStatsDelta(delta: any)
	-- If this is a full sync, (re)initialize state
	if delta and delta.type == StatTypeUtil.DeltaTypes.FULL_SYNC and delta.data then
		debugLog("Received FULL_SYNC delta")
		local ok, deserialized = pcall(function()
			return StatTypeUtil.deserializeStats(delta.data)
		end)
		if ok then
			currentStats = deserialized
			debugLog("Applied full sync delta payload")
		else
			warn("StatsClient: Failed to deserialize full_sync:", deserialized)
		end
		return
	end

	if not currentStats then
		-- If no state yet, proactively request a full sync and skip applying this incremental delta
		-- The server should also push a full_sync on join, but this hardens against ordering races
		requestStats()
		return
	end

	local success = pcall(function()
		StatTypeUtil.applyDelta(currentStats :: StatTypes.PlayerStats, delta)
	end)

	if not success then
		warn("StatsClient: Failed to apply delta")
	else
		debugLog("Applied incremental delta", delta and delta.type or "UNKNOWN", delta and delta.target or "")
		notifyChange({ kind = "delta", delta = delta })
	end
end

-- Request fresh stats data from server
-- requestStats defined above

local _statsDeltaDisconnect = (dispatcher :: any):on("StatsDelta", onStatsDelta)

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

function StatsClient.onChanged(callback: (StatTypes.PlayerStats, ChangeContext) -> ()): () -> ()
	local connection = changeSignal.Event:Connect(function(stats, context)
		callback(stats, context)
	end)
	return function()
		if connection.Connected then
			connection:Disconnect()
		end
	end
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
