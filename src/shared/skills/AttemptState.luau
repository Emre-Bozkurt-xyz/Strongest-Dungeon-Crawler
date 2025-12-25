--!strict
-- Shared SkillAttempt lifecycle helpers
-- Defines canonical attempt states and allowed transitions for both client and server.

local AttemptState = {}

export type State = "idle" | "local_predicted" | "pending_server" | "server_confirmed" | "rejected" | "completed"

AttemptState.States = {
	Idle = "idle",
	LocalPredicted = "local_predicted",
	PendingServer = "pending_server",
	ServerConfirmed = "server_confirmed",
	Rejected = "rejected",
	Completed = "completed",
}

-- Allowed state transitions; used to enforce a consistent attempt lifecycle across client/server.
local allowed: { [State]: { [State]: boolean } } = {
	["idle"] = {
		["local_predicted"] = true,
	},
	["local_predicted"] = {
		["pending_server"] = true,
		["rejected"] = true, -- local reject before server reply
	},
	["pending_server"] = {
		["server_confirmed"] = true,
		["rejected"] = true,
	},
	["server_confirmed"] = {
		["completed"] = true,
		["rejected"] = true, -- for late rejection/cancel cases
	},
	["rejected"] = {},
	["completed"] = {},
}

function AttemptState.isValid(state: string?): boolean
	return state == "idle"
		or state == "local_predicted"
		or state == "pending_server"
		or state == "server_confirmed"
		or state == "rejected"
		or state == "completed"
end

function AttemptState.canTransition(from: State, to: State): boolean
	local map = allowed[from]
	if not map then
		return false
	end
	return map[to] == true
end

return AttemptState
