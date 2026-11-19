--!strict
-- Debug flags for the client realm. The server has its own DebugConfig instance, so these are
-- separate from the server's `flag` and `flags`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugConfig = require(ReplicatedStorage.Shared.Debug.DebugConfig)

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
		name = "cflag",
		group = "Debug",
		summary = "Turn a client debug flag on or off",
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
		name = "cflags",
		group = "Debug",
		summary = "List the client debug flags and their values",
		run = function()
			local all = DebugConfig.getAll()
			local lines: { string } = {}
			for _, name in ipairs(flagNames()) do
				table.insert(lines, `{name} = {all[name]}`)
			end
			return { message = table.concat(lines, "\n"), data = all }
		end,
	},
}
