--!strict
-- Client-side attributes display and handling

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local warp = require(ReplicatedStorage.Packages.warp)
local StatTypeUtil = require(ReplicatedStorage.Shared.StatTypeUtil)
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)
local SystemPanelHandler = require(script.Parent.SystemPanelHandler)

local StatsClient = {}
StatsClient.__index = StatsClient

local statsRequestEvent = warp.Client("StatsRequest")
local statsDeltaEvent = warp.Client("StatsDelta") -- Delta update event

local statsReceivedSignal = warp.Signal("StatsReceived")

function StatsClient.new()
	local self = setmetatable({}, StatsClient)

	self.currentStats = {} :: StatTypes.PlayerStats
	self.lastRequestTime = 0 -- Rate limiting for full sync requests

	-- Initialize the system panel handler
	self.systemPanelHandler = SystemPanelHandler.new()

	-- Connect to delta update event (incremental updates)
	statsDeltaEvent:Connect(function(deltaUpdate)
		self:handleDeltaUpdate(deltaUpdate)
	end)

	print("StatsClient initialized")
	return self
end

function StatsClient:displayStats()
	self.systemPanelHandler:displayPanel()
end

function StatsClient:requestStatsUpdate()
	-- Rate limit requests to prevent spam (1 second cooldown)
	local currentTime = tick()
	if currentTime - self.lastRequestTime < 1 then
		return -- Skip request if within cooldown
	end
	self.lastRequestTime = currentTime

	-- Request the server to send the latest stats
	statsRequestEvent:Fire(true)
	print("Requested full stats sync from server")
end

function StatsClient:handleDeltaUpdate(deltaUpdate: any)
	-- Handle incremental updates to avoid recreating stat instances
	if not deltaUpdate then
		warn("Received nil delta update")
		return
	end

	local success = false

	if deltaUpdate.type == "batch" then
		-- Handle batched deltas
		if not self.currentStats then
			warn("Received batched delta update but no current stats - requesting full sync")
			self:requestStatsUpdate()
			return
		end

		local successCount = StatTypeUtil.applyBatchedDeltas(self.currentStats, deltaUpdate)
		success = successCount > 0
		print(`Applied {successCount}/{#deltaUpdate.deltas} delta updates`)
	elseif deltaUpdate.type == "full_sync" then
		-- Handle full sync - deserialize the complete stats
		if deltaUpdate.stat == "ALL_STATS" and deltaUpdate.data then
			self.currentStats = StatTypeUtil.deserializeStats(deltaUpdate.data)
			success = true
			print("Applied full sync update - stats initialized")
		else
			warn(
				`Invalid full sync delta structure - stat: {deltaUpdate.stat or "nil"}, data: {deltaUpdate.data and "present" or "nil"}`
			)
		end
	else
		-- Handle single delta
		if not self.currentStats then
			warn("Received delta update but no current stats - requesting full sync")
			self:requestStatsUpdate()
			return
		end

		success = StatTypeUtil.applyDelta(self.currentStats, deltaUpdate)
		if success then
			print(`Applied delta: {deltaUpdate.type} for {deltaUpdate.stat}`)
		end
	end

	if success then
		-- Notify UI that stats changed (but without recreating instances)
		statsReceivedSignal:Fire(self.currentStats)
	else
		warn("Failed to apply delta update - requesting full sync")
		self:requestStatsUpdate()
	end
end

return StatsClient
