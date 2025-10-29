--!strict
-- ProjectileEvent: dedicated dispatcher channel for projectile visual updates

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Networking = require(ReplicatedStorage.Shared.Networking)

local CHANNEL = "Projectiles"
local dispatcher = Networking.server()
local dispatcherAny = dispatcher :: any
dispatcherAny:_ensureChannel(CHANNEL)

local DEFAULT_QOS = "HIGH"

local ProjectileEvent = {}

-- NOTE: RequestShoot handling moved to `ProjectileRPC.luau` to avoid cyclic requires between
-- ProjectileService <-> ProjectileEvent. See that module for the server-side RequestShoot handler.

function ProjectileEvent:FireAllClients(payload: any)
	dispatcherAny:emit("ProjectileEvent", payload, {
		qos = DEFAULT_QOS,
	})
end

function ProjectileEvent:FireClient(player: Player, payload: any)
	dispatcherAny:emit("ProjectileEvent", payload, {
		targets = player,
		qos = DEFAULT_QOS,
	})
end

return ProjectileEvent
