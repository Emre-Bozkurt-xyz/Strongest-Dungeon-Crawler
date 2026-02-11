--!strict
-- TimeSync: maintains a smoothed client<->server time offset using os.clock().

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Networking = require(ReplicatedStorage.Shared.Networking)

local TimeSync = {}

local dispatcher = Networking.client()
local dispatcherAny = dispatcher :: any
dispatcherAny:_ensureChannel("TimeSync")

local SAMPLE_INTERVAL = 2.0
local OFFSET_ALPHA = 0.1
local RTT_ALPHA = 0.2

local running = false
local offset = 0.0 -- clientLocalTime - serverTime
local rtt = 0.0
local lastSampleAt = 0.0
local hasSample = false

local function applySample(clientSentAt: number, clientRecvAt: number, serverTime: number)
	local sampleRtt = clientRecvAt - clientSentAt
	local serverAtRecv = serverTime + (sampleRtt * 0.5)
	local sampleOffset = clientRecvAt - serverAtRecv

	if not hasSample then
		offset = sampleOffset
		rtt = sampleRtt
		hasSample = true
	else
		offset = offset * (1 - OFFSET_ALPHA) + sampleOffset * OFFSET_ALPHA
		rtt = rtt * (1 - RTT_ALPHA) + sampleRtt * RTT_ALPHA
	end

	lastSampleAt = clientRecvAt
end

local function sampleOnce()
	local sentAt = os.clock()
	local response = dispatcher:request("TimeSyncRequest", {
		clientTime = sentAt,
	})
	local recvAt = os.clock()
	if not response or response.ok == false then
		return
	end
	if type(response.serverTime) ~= "number" then
		return
	end
	applySample(sentAt, recvAt, response.serverTime)
end

function TimeSync.start()
	if running then
		return
	end
	running = true
	task.spawn(function()
		while running do
			sampleOnce()
			task.wait(SAMPLE_INTERVAL)
		end
	end)
end

function TimeSync.stop()
	running = false
end

function TimeSync.sample()
	sampleOnce()
end

function TimeSync.hasSample(): boolean
	return hasSample
end

function TimeSync.getOffset(): number
	return offset
end

function TimeSync.getRTT(): number
	return rtt
end

function TimeSync.getLastSampleAge(): number
	if lastSampleAt <= 0 then
		return math.huge
	end
	return os.clock() - lastSampleAt
end

function TimeSync.toServerTime(clientTime: number): number
	return clientTime - offset
end

function TimeSync.toClientTime(serverTime: number): number
	return serverTime + offset
end

function TimeSync.getServerNow(): number
	return os.clock() - offset
end

return TimeSync
