--!strict
-- TimeSyncService: publishes how the server's clock relates to Roblox's synced clock.
--
-- Server timestamps in this codebase are os.clock() values: combo windows, cooldowns, movement and
-- input times all live in that domain. Clients cannot read that clock, but every peer can read
-- workspace:GetServerTimeNow(), which the engine keeps in sync. Publishing the gap between the two
-- lets a client convert between them on any frame, with no round trips of its own to sample, smooth
-- or be biased by asymmetric latency.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TimeSyncService = {}

local ATTRIBUTE = "ServerClockBias"
-- Both clocks advance at real-time rate, so the gap is near constant; refreshing only absorbs slow
-- drift between them over a long session.
local REFRESH_INTERVAL = 10

local started = false

local function publish()
	ReplicatedStorage:SetAttribute(ATTRIBUTE, os.clock() - workspace:GetServerTimeNow())
end

function TimeSyncService.start()
	if started then
		return
	end
	started = true
	publish()
	task.spawn(function()
		while started do
			task.wait(REFRESH_INTERVAL)
			publish()
		end
	end)
end

function TimeSyncService.stop()
	started = false
end

return TimeSyncService
