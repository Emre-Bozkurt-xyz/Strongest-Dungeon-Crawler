--!strict
-- Scenarios (dev/Scenarios): load, reload, leave, list, and what pressing Play loads.

local Support = require(script.Parent.Parent.CommandSupport)

local function scenarios(): any
	return Support.load("dev.Scenarios")
end

local function ids(): { string }
	return scenarios().ids()
end

local function bootChoices(): { string }
	local list = { "last", "default" }
	for _, id in ipairs(ids()) do
		if id ~= "default" then
			table.insert(list, id)
		end
	end
	return list
end

local function describe(info: any): string
	local parts = { info.id }
	if info.title ~= info.id then
		table.insert(parts, `"{info.title}"`)
	end
	if info.stage then
		table.insert(parts, `stage {info.stage}`)
	end
	if info.character ~= "keep" then
		table.insert(parts, `character {info.character}`)
	end
	if info.source == "stage" then
		table.insert(parts, "(from the stage)")
	end
	return table.concat(parts, "  ")
end

return {
	{
		name = "scenario load",
		group = "Scenario",
		summary = "Load a scenario: its stage, character (on you) and setup",
		args = {
			{ name = "id", type = "choice", choices = ids },
		},
		run = function(context, args)
			local module = scenarios()
			local ok, err = module.load(args.id, context.player)
			if not ok then
				Support.fail(err or "could not load")
			end
			return { message = `loaded {args.id}`, data = module.current() }
		end,
	},
	{
		name = "scenario reload",
		group = "Scenario",
		summary = "Load the current scenario again from scratch",
		run = function()
			local module = scenarios()
			local ok, err = module.reload()
			if not ok then
				Support.fail(err or "could not reload")
			end
			local info = module.current()
			return { message = `reloaded {info and info.id or "?"}`, data = info }
		end,
	},
	{
		name = "scenario exit",
		group = "Scenario",
		summary = "Leave the scenario: unload its stage, restore real saves, return to the world spawn",
		run = function()
			local ok, err = scenarios().exit()
			if not ok then
				Support.fail(err or "could not exit")
			end
			return "left the scenario"
		end,
	},
	{
		name = "scenario list",
		group = "Scenario",
		summary = "List the scenarios, from code and from stages",
		run = function()
			local list = scenarios().list()
			local lines: { string } = {}
			for _, info in ipairs(list) do
				table.insert(lines, `{if info.current then "* " else "  "}{describe(info)}`)
			end
			return { message = table.concat(lines, "\n"), data = { scenarios = list } }
		end,
	},
	{
		name = "scenario current",
		group = "Scenario",
		summary = "Which scenario is loaded",
		run = function()
			local info = scenarios().current()
			if not info then
				return { message = "no scenario is loaded", data = {} }
			end
			return { message = describe(info), data = info }
		end,
	},
	{
		name = "scenario boot",
		group = "Scenario",
		summary = "Choose what pressing Play loads for you: the last scenario, the default, or a fixed one; with no target, show the choice",
		args = {
			{ name = "target", type = "choice", optional = true, choices = bootChoices },
		},
		run = function(context, args)
			local player = Support.playerEntity(context)
			if args.target == nil then
				local id, pin = scenarios().bootTarget(player)
				return { message = `boot: {pin} (pressing Play loads {id})`, data = { boot = pin, target = id } }
			end
			local ok, stored = scenarios().setBoot(player, args.target)
			if not ok then
				Support.fail(stored or "could not save")
			end
			return { message = `pressing Play loads: {stored}`, data = { boot = stored } }
		end,
	},
}
