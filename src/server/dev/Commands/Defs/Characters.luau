--!strict
-- Character presets on the calling player (dev/Characters): apply, restore, capture.

local Support = require(script.Parent.Parent.CommandSupport)

local function characters(): any
	return Support.load("dev.Characters")
end

local function presetNames(): { string }
	return characters().list()
end

local NAME_PATTERN = "^[%w_%-]+$"

local function specData(name: string, spec: any, source: string): any
	return { name = name, spec = Support.jsonSafe(spec), source = source }
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
			local presets = {}
			local lines: { string } = {}
			for _, name in ipairs(module.list()) do
				local source = module.presetSource(name) or "file"
				table.insert(presets, { name = name, source = source, current = name == current })
				table.insert(lines, `{if name == current then "* " else "  "}{name}{if source == "session" then " (saved this session)" else ""}`)
			end
			return { message = table.concat(lines, "\n"), data = { presets = presets, current = current or "" } }
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
		summary = "Capture your live build as a preset for this session and print its Luau source",
		args = {
			{ name = "name", type = "string" },
		},
		run = function(context, args)
			local player = Support.playerEntity(context)
			local name: string = args.name
			if not string.match(name, NAME_PATTERN) then
				Support.fail("a preset name is letters, digits, '-' and '_'")
			end
			local source = characters().save(player, name)
			local path = `src/server/dev/Characters/Presets/{name}.luau`
			print(`[Characters] captured '{name}' (paste into {path}):\n{source}`)
			return {
				message = `saved '{name}' for this session; its source is in the output, for {path}`,
				data = { name = name, path = path, source = source },
			}
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
}
