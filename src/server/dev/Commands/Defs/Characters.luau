--!strict
-- Character presets and the character editor on the calling player (dev/Characters): apply,
-- restore, capture, save and delete presets; read the editor's schema and state; edit the live build.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StatTypes = require(ReplicatedStorage.Shared.StatTypes)
local Support = require(script.Parent.Parent.CommandSupport)

local function characters(): any
	return Support.load("dev.Characters")
end

local function presetNames(): { string }
	return characters().list()
end

local function savedNames(): { string }
	local module = characters()
	local names: { string } = {}
	for _, name in ipairs(module.list()) do
		if module.presetSource(name) ~= "file" then
			table.insert(names, name)
		end
	end
	return names
end

local function poolNames(): { string }
	local names: { string } = {}
	for name in pairs(StatTypes.PoolStats) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

local function specData(name: string, spec: any, source: string): any
	return { name = name, spec = Support.jsonSafe(spec), source = source }
end

-- An editor command's answer: its message, and the live state after it (refused or not), so the
-- editor redraws from one round trip.
local function editAnswer(player: Player, result: any): any
	return {
		ok = result.ok,
		message = result.message,
		data = {
			problems = result.problems,
			inPlace = result.inPlace,
			state = Support.jsonSafe(characters().state(player)),
		},
	}
end

return {
	{
		name = "character apply",
		group = "Character",
		summary = "Put a character preset on you (your real save is set aside, not changed)",
		args = {
			{ name = "preset", type = "choice", choices = presetNames },
		},
		run = function(context, args)
			local player = Support.playerEntity(context)
			local ok, err = characters().apply(player, args.preset)
			if not ok then
				Support.fail(err or "could not apply")
			end
			return { message = `applied {args.preset}`, data = { name = args.preset } }
		end,
	},
	{
		name = "character restore",
		group = "Character",
		summary = "Go back to your real save",
		run = function(context)
			local player = Support.playerEntity(context)
			local ok, err = characters().restore(player)
			if not ok then
				Support.fail(err or "could not restore")
			end
			return "back on your real save"
		end,
	},
	{
		name = "character list",
		group = "Character",
		summary = "List the character presets",
		run = function(context)
			local module = characters()
			local current = if context.player then module.current(context.player) else nil
			local persists, why = module.storeStatus()
			local presets = {}
			local lines: { string } = {}
			for _, name in ipairs(module.list()) do
				local source = module.presetSource(name) or "file"
				table.insert(presets, { name = name, source = source, current = name == current })
				local note = if source == "saved" then " (saved)" elseif source == "session" then " (this session only)" else ""
				table.insert(lines, `{if name == current then "* " else "  "}{name}{note}`)
			end
			return {
				message = table.concat(lines, "\n"),
				data = { presets = presets, current = current or "", store = { persists = persists, reason = why } },
			}
		end,
	},
	{
		name = "character current",
		group = "Character",
		summary = "Which preset you are playing, if any",
		run = function(context)
			local player = Support.playerEntity(context)
			local name = characters().current(player)
			return {
				message = if name then `playing {name}` else "on your real save",
				data = { name = name or "", sandboxed = name ~= nil },
			}
		end,
	},
	{
		name = "character save",
		group = "Character",
		summary = "Save your live build as a preset (kept in the dev preset store) and print its Luau source",
		args = {
			{ name = "name", type = "string" },
		},
		run = function(context, args)
			local player = Support.playerEntity(context)
			local name: string = args.name
			local result = characters().save(player, name)
			if not result.ok then
				Support.fail(result.message)
			end
			local path = `src/server/dev/Characters/Presets/{name}.luau`
			print(`[Characters] saved '{name}' (to keep it as a file, paste into {path}):\n{result.source}`)
			return {
				message = result.message,
				data = { name = name, path = path, source = result.source, storage = result.storage },
			}
		end,
	},
	{
		name = "character delete",
		group = "Character",
		summary = "Delete a saved preset",
		args = {
			{ name = "preset", type = "choice", choices = savedNames },
		},
		run = function(_context, args)
			local ok, message = characters().delete(args.preset)
			if not ok then
				Support.fail(message)
			end
			return { message = message, data = { name = args.preset } }
		end,
	},
	{
		name = "character show",
		group = "Character",
		summary = "Show a preset's resolved spec, or your live build when no preset is named",
		args = {
			{ name = "preset", type = "choice", optional = true, choices = presetNames },
		},
		run = function(context, args)
			local module = characters()
			local preset: string? = args.preset
			local name: string
			local spec: any
			if preset then
				name = preset
				spec = module.get(preset)
				if not spec then
					Support.fail(`preset '{preset}' does not resolve`)
				end
			else
				local player = Support.playerEntity(context)
				name = module.current(player) or "live"
				spec = module.capture(player)
			end
			local source = module.toLuau(spec)
			return { message = source, data = specData(name, spec, source) }
		end,
	},
	{
		name = "character schema",
		group = "Character",
		summary = "Every choice and limit the character editor offers (attributes, curves, nodes, items...)",
		run = function()
			return { message = "character editor schema", data = characters().schema() }
		end,
	},
	{
		name = "character state",
		group = "Character",
		summary = "Your live build as a spec, with the editor's read-outs and what was edited",
		run = function(context)
			local player = Support.playerEntity(context)
			local state = characters().state(player)
			if not state then
				Support.fail("your save has not loaded")
			end
			local edited = if #state.edited > 0 then `, edited: {state.editedSummary}` else ""
			local where = if state.sandboxed then `on {state.name}` else "on your real save"
			return { message = `level {state.level}, {where}{edited}`, data = Support.jsonSafe(state) }
		end,
	},
	{
		name = "character set",
		group = "Character",
		summary = "Edit your live build with a partial spec (on the real save, moves you to a sandbox copy first)",
		args = {
			{ name = "patch", type = "json" },
		},
		run = function(context, args)
			local player = Support.playerEntity(context)
			return editAnswer(player, characters().edit(player, args.patch))
		end,
	},
	{
		name = "character revert",
		group = "Character",
		summary = "Undo every edit: re-apply the base preset (a copy of the real save goes back to it)",
		run = function(context)
			local player = Support.playerEntity(context)
			local ok, message = characters().revert(player)
			if not ok then
				Support.fail(message)
			end
			return message
		end,
	},
	{
		name = "character unlock",
		group = "Character",
		summary = "Raise a mastery track to open a node (id or name)",
		args = {
			{ name = "node", type = "rest" },
		},
		run = function(context, args)
			local player = Support.playerEntity(context)
			return editAnswer(player, characters().unlock(player, args.node))
		end,
	},
	{
		name = "character pool",
		group = "Character",
		summary = "Set a pool to an amount, a percentage, full or empty",
		args = {
			{ name = "pool", type = "choice", choices = poolNames },
			{ name = "value", type = "string" },
		},
		run = function(context, args)
			local player = Support.playerEntity(context)
			return editAnswer(player, characters().setPool(player, args.pool, args.value))
		end,
	},
	{
		name = "character hold",
		group = "Character",
		summary = "Hold a pool at its current value through damage, costs and regeneration, or release it",
		args = {
			{ name = "pool", type = "choice", choices = poolNames },
			{ name = "on", type = "boolean", default = true },
		},
		run = function(context, args)
			local player = Support.playerEntity(context)
			local ok, message = characters().hold(player, args.pool, args.on)
			return editAnswer(player, { ok = ok, message = message })
		end,
	},
}
