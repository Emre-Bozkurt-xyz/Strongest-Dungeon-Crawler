--!strict
-- TimeSync: the server's clock (os.clock() on the server) as seen from this client.
--
-- Read as workspace:GetServerTimeNow() plus the gap TimeSyncService publishes between the server's
-- os.clock() and that synced clock. The engine maintains GetServerTimeNow(), so there is nothing to
-- sample or smooth here, and the estimate is not skewed by latency that differs in each direction.
--
-- `offset` keeps its meaning for callers: this client's os.clock() minus server time.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TimeSync = {}

local ATTRIBUTE = "ServerClockBias"
-- The server publishes the gap at startup, so it normally arrives with the initial replication; the
-- wait only covers a client that starts before it lands.
local READY_TIMEOUT = 10

local bias: number? = nil
local started = false

local function readBias()
	local value = ReplicatedStorage:GetAttribute(ATTRIBUTE)
	if type(value) == "number" then
		bias = value
	end
end

function TimeSync.start()
	if started then
		return
	end
	started = true
	ReplicatedStorage:GetAttributeChangedSignal(ATTRIBUTE):Connect(readBias)
	readBias()
	local deadline = os.clock() + READY_TIMEOUT
	while bias == nil and os.clock() < deadline do
		task.wait()
	end
	if bias == nil then
		warn(`[TimeSync] '{ATTRIBUTE}' was not published within {READY_TIMEOUT}s; server times will be wrong until it is`)
	end
end

function TimeSync.isReady(): boolean
	return bias ~= nil
end

function TimeSync.getServerNow(): number
	return workspace:GetServerTimeNow() + (bias or 0)
end

function TimeSync.getOffset(): number
	return os.clock() - TimeSync.getServerNow()
end

function TimeSync.toServerTime(clientTime: number): number
	return clientTime - TimeSync.getOffset()
end

function TimeSync.toClientTime(serverTime: number): number
	return serverTime + TimeSync.getOffset()
end

return TimeSync
