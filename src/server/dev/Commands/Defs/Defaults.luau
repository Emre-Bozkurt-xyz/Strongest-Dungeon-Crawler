--!strict
-- Game defaults tuned live (dev/GameDefaults): list StatsConfig's defaults, change one for this
-- session, reset, and export the changed ones as Luau for StatsConfig.luau. Session-only; nothing is
-- saved.

local Support = require(script.Parent.Parent.CommandSupport)

local function defaults(): any
	return Support.load("dev.GameDefaults")
end

local function statNames(): { string }
	local names: { string } = {}
	for _, row in ipairs(defaults().list()) do
		table.insert(names, row.stat)
	end
	return names
end

local function fmt(value: number): string
	return tostring(value)
end

return {
	{
		name = "defaults",
		group = "Tuning",
		summary = "List the game's stat defaults: the file's value, this session's, and which are changed",
		args = {
			{ name = "filter", type = "string", optional = true },
		},
		run = function(_context, args)
			local filter: string? = if args.filter then string.lower(args.filter) else nil
			local rows = {}
			local lines: { string } = {}
			local changed = 0
			for _, row in ipairs(defaults().list()) do
				if row.changed then
					changed += 1
				end
				if filter == nil or string.find(string.lower(row.stat), filter, 1, true) then
					table.insert(rows, row)
					table.insert(
						lines,
						`{if row.changed then "* " else "  "}{row.stat} ({row.kind}) = {fmt(row.value)}{if row.changed
							then ` (file {fmt(row.file)})`
							else ""}`
					)
				end
			end
			table.insert(lines, `{changed} changed this session; session-only, gone when Play stops`)
			return {
				message = table.concat(lines, "\n"),
				data = { defaults = rows, changed = changed, sessionOnly = true },
			}
		end,
	},
	{
		name = "defaults set",
		group = "Tuning",
		summary = "Change a stat's game default for this session; live entities that inherit it follow at once",
		args = {
			{ name = "stat", type = "choice", choices = statNames },
			{ name = "value", type = "number" },
		},
		run = function(_context, args)
			local result, err = defaults().set(args.stat, args.value)
			if not result then
				Support.fail(err or "could not set")
			end
			local parts = { `{result.inherited} live inherit it` }
			if result.overridden > 0 then
				table.insert(parts, `{result.overridden} of them keep an override`)
			end
			if result.ownDefault > 0 then
				table.insert(parts, `{result.ownDefault} set their own`)
			end
			local clamped = if result.clamped then ` (clamped to {fmt(result.min)}..{fmt(result.max)})` else ""
			return {
				message = `{result.stat} default {fmt(result.value)}{clamped}, file {fmt(result.file)}: {table.concat(parts, ", ")}; session-only`,
				data = result,
			}
		end,
	},
	{
		name = "defaults reset",
		group = "Tuning",
		summary = "Put a stat's game default back to the file's value, or every changed one",
		args = {
			{ name = "stat", type = "choice", optional = true, choices = statNames },
		},
		run = function(_context, args)
			local reset, err = defaults().reset(args.stat)
			if not reset then
				Support.fail(err or "could not reset")
			end
			return {
				message = if #reset > 0 then `reset {table.concat(reset, ", ")} to the file's values` else "nothing was changed",
				data = { reset = reset },
			}
		end,
	},
	{
		name = "defaults export",
		group = "Tuning",
		summary = "The defaults changed this session as StatsConfig.luau entries to paste (they do not persist otherwise)",
		run = function()
			local luau, changes = defaults().export()
			if #changes == 0 then
				return { message = "no default is changed this session", data = { luau = "", changes = changes } }
			end
			print(`[GameDefaults] replace these entries in src/server/Stats/Config/StatsConfig.luau:\n{luau}`)
			return {
				message = luau,
				data = { path = "src/server/Stats/Config/StatsConfig.luau", luau = luau, changes = changes },
			}
		end,
	},
}
