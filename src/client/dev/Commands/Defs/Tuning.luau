--!strict
-- Live tuning of Shared.Config values (DevTuningService).

local devFolder = script:FindFirstAncestor("dev")
assert(devFolder, "client command defs must live under the dev folder")
local DevTuningService = require(devFolder:FindFirstChild("DevTuningService") :: ModuleScript)

return {
	{
		name = "tune",
		group = "Tuning",
		summary = "Run a tuning command (get, set, setmany, nudge, reset, paths, ...); 'tune help' lists them",
		args = {
			{ name = "command", type = "rest", default = "help" },
		},
		run = function(_context, args)
			local success, lines = DevTuningService.executeCommand(args.command)
			local message = table.concat(lines, "\n")
			if message == "" then
				message = if success then "ok" else "tune command failed"
			end
			return { ok = success, message = message, data = { lines = lines } }
		end,
	},
}
