--!strict
-- Client-side stats display and handling

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StatTypeUtil = require(ReplicatedStorage.Shared.StatTypeUtil)
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)
local ClientNetworkManager = require(script.Parent.ClientNetworkManager)

-- Import shared types
local NetworkTypes = require(game.ReplicatedStorage.Shared.NetworkTypes)
type Delta = NetworkTypes.Delta

-- Stats handler for ClientNetworkManager
local statsHandler = {
	deserialize = function(data: any): StatTypes.PlayerStats
		return StatTypeUtil.deserializeStats(data)
	end,
	applyDelta = function(currentData: StatTypes.PlayerStats, delta: Delta): boolean
		-- StatTypeUtil now handles both old and new delta formats
		return StatTypeUtil.applyDelta(currentData, delta)
	end,
	serialize = function(data: StatTypes.PlayerStats): any
		return StatTypeUtil.serializeStats(data)
	end,
}

-- Initialize stats system
local function initializeStats()
	-- Register stats system with ClientNetworkManager
	ClientNetworkManager.registerSystem("stats", statsHandler, {})

	print("📊 StatsClient: Initialized with centralized NetworkManager")
end

-- Public API
local StatsClient = {}

-- Get current stats data from ClientNetworkManager
function StatsClient.getCurrentStats(): StatTypes.PlayerStats?
	return ClientNetworkManager.getSystemData("stats")
end

-- Get formatted stats for UI display
function StatsClient.getFormattedStats(): StatTypes.PlayerStats?
	local rawData = ClientNetworkManager.getSystemData("stats")
	if not rawData then
		-- Request data if we don't have it yet
		StatsClient.requestStatsUpdate()
		return nil
	end

	-- Check what type of data we're getting
	if type(rawData) == "table" then
		-- Check if it's already deserialized stats objects
		if rawData.Health and type(rawData.Health) == "table" and rawData.Health.getValue then
			return rawData
		else
			-- Try to deserialize it
			local success, result = pcall(function()
				return StatTypeUtil.deserializeStats(rawData)
			end)

			if success then
				return result
			else
				warn(`📊 StatsClient: Failed to deserialize stats: {result}`)
				return nil
			end
		end
	end

	warn("📊 StatsClient: Invalid data type received:", type(rawData))
	return nil
end

-- Request fresh stats data from server
function StatsClient.requestStatsUpdate()
	-- Request the server to send the latest stats via ClientNetworkManager
	ClientNetworkManager.requestSystemData("stats")
	print("📥 StatsClient: Requested stats from server")
end

-- Initialize when script loads
initializeStats()

return StatsClient
