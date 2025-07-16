--!strict
-- Client-side attributes display and handling

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local warp = require(ReplicatedStorage.Packages.warp)
local StatTypeUtil = require(ReplicatedStorage.Shared.StatTypeUtil)
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)
local SystemPanelHandler = require(script.Parent.SystemPanelHandler)

local StatsClient = {}
StatsClient.__index = StatsClient

local statsUpdateEvent = warp.Client("StatsUpdate")
local statsRequestEvent = warp.Client("StatsRequest")

local statsReceivedSignal = warp.Signal("StatsReceived")

function StatsClient.new()
	local self = setmetatable({}, StatsClient)

	self.currentStats = {} :: StatTypes.PlayerStats

	-- Initialize the system panel handler
	self.systemPanelHandler = SystemPanelHandler.new()

	-- Connect to stats update event
	statsUpdateEvent:Connect(function(newStats)
		self:handleStatsUpdate(newStats)
	end)

	print("StatsClient initialized")
	return self
end

function StatsClient:displayStats()
	self.systemPanelHandler:displayStats()
end

function StatsClient.requestAttributesUpdate()
	-- Request the server to send the latest attributes
	statsRequestEvent:Fire(true)
end

function StatsClient:handleStatsUpdate(newStats: { [string]: any })
	-- Deserialize and update stats
	if not newStats then
		warn("Received nil stats update")
		return
	end

	self.currentStats = StatTypeUtil.deserializeStats(newStats)

	statsReceivedSignal:Fire(self.currentStats)
	print("StatsClient received stats update from server")
end

return StatsClient
