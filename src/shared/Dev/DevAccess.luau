--!strict
-- DevAccess: who may use dev tooling. The server asks `canUse` for every dev request; the client
-- only uses `isEnabled` to decide whether to build its console at all, never as authorization.
--
-- Dev tooling is Studio only. Opening it to chosen users on live servers would need more than a
-- per-user check here: the DevHooks bootstrap entries are Studio gated, and the dev session-start
-- hook grants the starter kit and boots a scenario for every player, so widening that gate would
-- change the game for everyone in the server. It would need per-player session hooks and a client
-- gate that knows its own UserId is allowed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugConfig = require(ReplicatedStorage.Shared.Debug.DebugConfig)

local DevAccess = {}

-- Whether dev tooling exists in this session at all.
function DevAccess.isEnabled(): boolean
	return DebugConfig.isDev()
end

-- The single server-side authorization point for dev requests.
function DevAccess.canUse(_player: Player): boolean
	return DebugConfig.isDev()
end

return DevAccess
