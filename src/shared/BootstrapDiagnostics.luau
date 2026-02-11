--!strict
-- Shared bootstrap diagnostics helpers (server/client).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DebugConfig = require(ReplicatedStorage.Shared.Debug.DebugConfig)

local Diagnostics = {}

export type DiagEntry = {
	kind: "info" | "warn" | "error",
	message: string,
}

local function emit(entry: DiagEntry)
	if not DebugConfig.isEnabled("bootstrap") then
		return
	end
	local prefix = "[Bootstrap]"
	if entry.kind == "error" then
		warn(`${prefix} ERROR: {entry.message}`)
	elseif entry.kind == "warn" then
		warn(`${prefix} WARN: {entry.message}`)
	else
		print(`${prefix} {entry.message}`)
	end
end

function Diagnostics.info(message: string)
	emit({ kind = "info", message = message })
end

function Diagnostics.warn(message: string)
	emit({ kind = "warn", message = message })
end

function Diagnostics.error(message: string)
	emit({ kind = "error", message = message })
end

function Diagnostics.assert(condition: boolean, message: string)
	if not condition then
		Diagnostics.error(message)
	end
end

return Diagnostics
