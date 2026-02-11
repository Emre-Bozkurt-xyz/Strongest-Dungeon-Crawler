--!strict
-- TimeSyncService: responds to client time sync requests with server timestamps.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Networking = require(ReplicatedStorage.Shared.Networking)

local TimeSyncService = {}

local dispatcher = Networking.server()
local dispatcherAny = dispatcher :: any
dispatcherAny:_ensureChannel("TimeSync")

local started = false
local requestDisconnect: (() -> ())? = nil

function TimeSyncService.start()
	if started then
		return
	end
	started = true

	requestDisconnect = dispatcherAny:onRequest("TimeSyncRequest", function(payload, _meta, context)
		local player = context.player
		if not player then
			return { ok = false, error = "no_player" }
		end

		local clientTime = payload and payload.clientTime
		local response = {
			ok = true,
			serverTime = os.clock(),
			clientTime = clientTime,
		}

		return response
	end)
end

function TimeSyncService.stop()
	if not started then
		return
	end
	started = false
	if requestDisconnect then
		requestDisconnect()
		requestDisconnect = nil
	end
end

return TimeSyncService
