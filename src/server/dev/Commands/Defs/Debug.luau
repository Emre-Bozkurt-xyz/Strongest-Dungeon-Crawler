--!strict
-- Debug flags for this realm and the command listing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CommandHelp = require(ReplicatedStorage.Shared.Dev.CommandHelp)
local DebugConfig = require(ReplicatedStorage.Shared.Debug.DebugConfig)
local Support = require(script.Parent.Parent.CommandSupport)

local function flagNames(): { string }
	local names: { string } = {}
	for name in pairs(DebugConfig.getAll()) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

return {
	{
		name = "flag",
		group = "Debug",
		summary = "Turn a server debug flag on or off",
		args = {
			{ name = "name", type = "choice", choices = flagNames },
			{ name = "value", type = "boolean" },
		},
		run = function(_context, args)
			DebugConfig.set(args.name, args.value)
			return `{args.name} = {args.value}`
		end,
	},
	{
		name = "flags",
		group = "Debug",
		summary = "List the server debug flags and their values",
		run = function()
			local all = DebugConfig.getAll()
			local lines: { string } = {}
			for _, name in ipairs(flagNames()) do
				table.insert(lines, `{name} = {all[name]}`)
			end
			return { message = table.concat(lines, "\n"), data = all }
		end,
	},
	{
		name = "help",
		group = "Debug",
		summary = "List the server commands by group, or show one command's usage",
		args = {
			{ name = "command", type = "rest", optional = true },
		},
		run = function(_context, args)
			local descriptors = Support.devCommands().describe()
			local query: string? = args.command
			if not query then
				return { message = CommandHelp.list(descriptors), data = { commands = descriptors } }
			end
			local text = CommandHelp.query(descriptors, query)
			if not text then
				Support.fail(`no command named '{query}'; try help`)
			end
			return text
		end,
	},
}
