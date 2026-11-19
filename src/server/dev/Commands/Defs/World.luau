--!strict
-- Stages, markers, teleports and NPCs. Stage commands load the map only; `scenario load <stage>`
-- also spawns what its markers ask for and applies its character.

local Support = require(script.Parent.Parent.CommandSupport)

-- How far in front of the player `spawn` puts NPCs, and how far apart a row of them stands.
local SPAWN_DISTANCE = 10
local SPAWN_SPACING = 5

local function stages(): any
	return Support.load("dev.Stages")
end

local function spawning(): any
	return Support.load("dev.Spawning")
end

local function stageNames(): { string }
	return stages().list()
end

local function kinds(): { string }
	return spawning().kinds()
end

local function despawnTargets(): { string }
	local list = { "all" }
	for _, kind in ipairs(kinds()) do
		table.insert(list, kind)
	end
	return list
end

local function markerNames(): { string }
	local module = stages()
	local names: { string } = {}
	local stage = module.current()
	for _, name in ipairs(if stage then stage:markerNames() else {}) do
		table.insert(names, name)
	end
	for _, name in ipairs(module.worldMarkerNames()) do
		if not table.find(names, name) then
			table.insert(names, name)
		end
	end
	return names
end

local function placeEveryone(cframe: CFrame)
	local module = stages()
	for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
		task.spawn(module.place, player, cframe)
	end
end

local function describeNpc(info: any): string
	local health = if info.health and info.maxHealth then ` {math.floor(info.health + 0.5)}/{math.floor(info.maxHealth + 0.5)}` else ""
	local position = info.position
	return `{info.kind} {info.entityId or "?"}{health}{if info.dead then " (dying)" else ""} at ({position[1]}, {position[2]}, {position[3]}){if info.tag then ` [{info.tag}]` else ""}`
end

return {
	{
		name = "stage load",
		group = "World",
		summary = "Load a stage from ServerStorage.Scenarios (map only) and move everyone to its start",
		args = {
			{ name = "name", type = "choice", choices = stageNames },
		},
		run = function(_context, args)
			local module = stages()
			local stage, err = module.load(args.name)
			if not stage then
				Support.fail(err or "could not load the stage")
			end
			placeEveryone(stage:playerStart())
			local markers = stage:markerNames()
			return {
				message = `loaded {stage.name}; markers: {if #markers > 0 then table.concat(markers, ", ") else "none"}`,
				data = { name = stage.name, markers = markers },
			}
		end,
	},
	{
		name = "stage unload",
		group = "World",
		summary = "Unload the stage and move everyone to the world spawn",
		run = function()
			local module = stages()
			if not module.current() then
				return "no stage is loaded"
			end
			module.unload()
			placeEveryone(module.worldStart())
			return "unloaded the stage"
		end,
	},
	{
		name = "stage list",
		group = "World",
		summary = "List the stages in ServerStorage.Scenarios",
		run = function()
			local module = stages()
			local current = module.current()
			local list = {}
			local lines: { string } = {}
			for _, name in ipairs(module.list()) do
				local isCurrent = current ~= nil and current.name == name
				table.insert(list, { name = name, current = isCurrent })
				table.insert(lines, `{if isCurrent then "* " else "  "}{name}`)
			end
			if #lines == 0 then
				table.insert(lines, "no stages (ServerStorage.Scenarios is empty or missing)")
			end
			return { message = table.concat(lines, "\n"), data = { stages = list } }
		end,
	},
	{
		name = "markers",
		group = "World",
		summary = "Show or hide scenario markers; with no argument, list them and whether they are shown",
		args = {
			{ name = "visibility", type = "choice", optional = true, choices = { "show", "hide" } },
		},
		run = function(_context, args)
			local module = stages()
			if args.visibility == nil then
				local stage = module.current()
				local stageMarkers = if stage then stage:markerNames() else {}
				local worldMarkers = module.worldMarkerNames()
				local visible = module.markersVisible()
				return {
					message = `markers {if visible then "shown" else "hidden"}; stage: {if #stageMarkers > 0
						then table.concat(stageMarkers, ", ")
						else "none"}; world: {if #worldMarkers > 0 then table.concat(worldMarkers, ", ") else "none"}`,
					data = {
						visible = visible,
						stage = if stage then stage.name else "",
						stageMarkers = stageMarkers,
						worldMarkers = worldMarkers,
					},
				}
			end
			local visible = args.visibility == "show"
			module.setMarkersVisible(visible)
			return { message = if visible then "markers shown" else "markers hidden", data = { visible = visible } }
		end,
	},
	{
		name = "tp",
		group = "World",
		summary = "Teleport to a marker on the stage, else in the world",
		args = {
			{ name = "marker", type = "string" },
		},
		run = function(context, args)
			local player = Support.playerEntity(context)
			local module = stages()
			local cframe = module.standAt(args.marker)
			if not cframe then
				local names = markerNames()
				Support.fail(`no marker named '{args.marker}' (markers: {if #names > 0 then table.concat(names, ", ") else "none"}; or tp start)`)
			end
			if not module.place(player, cframe) then
				Support.fail(`{player.Name} has no character to move`)
			end
			return `teleported to {args.marker}`
		end,
	},
	{
		name = "tp start",
		group = "World",
		summary = "Teleport to the stage's PlayerStart, or the world spawn when no stage is loaded",
		run = function(context)
			local player = Support.playerEntity(context)
			local module = stages()
			if not module.place(player, module.start()) then
				Support.fail(`{player.Name} has no character to move`)
			end
			return if module.current() then "teleported to the stage start" else "teleported to the world spawn"
		end,
	},
	{
		name = "spawn",
		group = "NPC",
		summary = "Spawn NPCs in front of you, on the ground; options are spawn options as JSON",
		args = {
			{ name = "kind", type = "choice", choices = kinds },
			{ name = "count", type = "integer", default = 1, min = 1, max = 50 },
			{ name = "options", type = "json", optional = true },
		},
		run = function(context, args)
			local player = Support.playerEntity(context)
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if not root or not root:IsA("BasePart") then
				Support.fail(`{player.Name} has no character`)
			end
			local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
			if look.Magnitude < 1e-3 then
				look = Vector3.new(0, 0, -1)
			end
			local center = root.Position + look.Unit * SPAWN_DISTANCE
			-- Facing the player, so the row runs across their view.
			local facing = CFrame.lookAt(center, center - look)
			local scenarioRow = Support.load("dev.Scenarios.Scope").row
			local scenarios = Support.load("dev.Scenarios")
			local options = args.options
			if options ~= nil and (type(options) ~= "table" or #options > 0) then
				Support.fail("options must be a JSON object, e.g. {\"respawnDelay\": 5}")
			end
			local names: { string } = {}
			for _, cframe in ipairs(scenarioRow(facing, args.count, SPAWN_SPACING)) do
				local model, err = scenarios.spawn(args.kind, cframe, options)
				if not model then
					Support.fail(err or `could not spawn {args.kind}`)
				end
				table.insert(names, model.Name)
			end
			return { message = `spawned {#names} {args.kind}`, data = { kind = args.kind, count = #names } }
		end,
	},
	{
		name = "despawn",
		group = "NPC",
		summary = "Remove NPCs (all, or one kind), dying ones and pending respawns included",
		args = {
			{ name = "target", type = "choice", choices = despawnTargets },
		},
		run = function(_context, args)
			local filter = if args.target == "all" then nil else { kind = args.target }
			local removed, cancelled = spawning().removeAll(filter)
			local message = `removed {removed} NPC(s)`
			if cancelled > 0 then
				message ..= ` and called off {cancelled} pending respawn(s)`
			end
			return { message = message, data = { removed = removed, cancelledRespawns = cancelled } }
		end,
	},
	{
		name = "npcs",
		group = "NPC",
		summary = "List the NPCs in the world",
		args = {
			{ name = "kind", type = "choice", optional = true, choices = kinds },
		},
		run = function(_context, args)
			local list = spawning().list(if args.kind then { kind = args.kind } else nil)
			local lines: { string } = {}
			for _, info in ipairs(list) do
				table.insert(lines, describeNpc(info))
			end
			if #lines == 0 then
				table.insert(lines, "no NPCs")
			end
			return { message = table.concat(lines, "\n"), data = { npcs = list } }
		end,
	},
}
