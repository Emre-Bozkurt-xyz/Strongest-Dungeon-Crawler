--!strict
-- `help` for both realms. It hides the server's own `help`, which only knows the server's commands.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CommandHelp = require(ReplicatedStorage.Shared.Dev.CommandHelp)
local CommandRegistry = require(ReplicatedStorage.Shared.Dev.CommandRegistry)

local function devCommandsClient(): any
	return require(script.Parent.Parent :: ModuleScript)
end

return {
	{
		name = "help",
		group = "Debug",
		summary = "List every command, client and server, by group; or show one command's usage",
		args = {
			{ name = "command", type = "rest", optional = true },
		},
		run = function(_context, args)
			local descriptors = devCommandsClient().refresh()
			local query: string? = args.command
			if not query then
				return { message = CommandHelp.list(descriptors), data = { commands = descriptors } }
			end
			local text = CommandHelp.query(descriptors, query)
			if not text then
				CommandRegistry.fail(`no command named '{query}'; try help`)
			end
			return text
		end,
	},
}
