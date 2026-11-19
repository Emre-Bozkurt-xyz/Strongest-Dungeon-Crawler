--!strict
-- Scenarios: named test setups a developer switches between mid-session, like switching worlds.
--
-- A scenario is a stage (Stages: a small map built in Studio), a character (Characters: a preset or
-- inline spec put on the invoking player) and an optional `setup` script, every part optional.
-- Definitions are the ModuleScripts under Defs, the id being the module's path below it
-- ("combat/status-marks"); each returns a table, optionally through `Scenarios.define`, which checks
-- it as the module loads. A stage that no definition names is a scenario by itself, with id = the
-- stage name and its Model attributes `Title`, `Description` and `Character` (a preset name) -- so a
-- scenario can be authored entirely in Studio.
--
-- The world is server-wide: one scenario is loaded at a time, and every player is placed at its
-- start. The character goes on the invoking player only.
--
-- Load order: tear down the current scenario, load the stage (or unload it, for the baseplate
-- world), spawn what the stage's markers ask for, apply the character, place players, apply debug
-- flags and client tuning, run `setup`. A step that fails is reported by name, what was built so far
-- is torn down and the default scenario is loaded in its place, so a failure never leaves a
-- half-loaded world.
--
-- State for UIs is replicated on ReplicatedStorage.DevState (attributes ScenarioId, ScenarioTitle,
-- StageName, Revision, plus ClientOverrides, the JSON the client dev code applies) and on each
-- Player (DevCharacter, set by Characters).

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DebugConfig = require(ReplicatedStorage.Shared.Debug.DebugConfig)
local DevAccess = require(ReplicatedStorage.Shared.Dev.DevAccess)

local devFolder = script.Parent
local Stages = require(devFolder.Stages)
local Spawning = require(devFolder.Spawning)
local Characters = require(devFolder.Characters)
local Scope = require(script.Scope)
local Persistence = require(script.Persistence)

export type Scope = Scope.Scope

export type Definition = {
	title: string?,
	description: string?,
	-- A stage name; left out, the scenario is in the baseplate world.
	stage: string?,
	-- A preset name, an inline spec, or "keep" (the default: the character is left as it is).
	character: any?,
	-- Server DebugConfig flags for the scenario's duration.
	flags: { [string]: boolean }?,
	-- Client DebugConfig flags for the scenario's duration.
	clientFlags: { [string]: boolean }?,
	-- Client DevTuningService overrides (dotted path -> value) for the scenario's duration.
	tune: { [string]: any }?,
	setup: ((Scope) -> ())?,
}

export type ScenarioInfo = {
	id: string,
	title: string,
	description: string,
	stage: string?,
	character: string,
	source: string,
	current: boolean,
}

type Entry = {
	id: string,
	source: string,
	def: Definition,
}

type Current = {
	entry: Entry,
	handle: Scope.Handle,
	player: Player?,
}

local Scenarios = {}

Scenarios.DEFAULT_ID = "default"
-- Every NPC a scenario spawns carries this tag, so teardown finds them whatever they did meanwhile.
Scenarios.SPAWN_TAG = "DevScenario"
-- NPCs spawned by command while no scenario is loaded.
Scenarios.LOOSE_TAG = "DevSpawn"

local KEEP = "keep"
local WORLD_FOLDER_NAME = "Scenario"
local STATE_NAME = "DevState"

local DEFINITION_FIELDS: { [string]: string } = {
	title = "string",
	description = "string",
	stage = "string",
	flags = "table",
	clientFlags = "table",
	tune = "table",
	setup = "function",
}

local current: Current? = nil
-- Definition problems already reported, so a broken module warns once rather than on every listing.
local reported: { [string]: boolean } = {}
local busy = false
local booted = false
local started = false
local state: Configuration? = nil

-- Checks a definition and returns it. Raising here makes a malformed definition fail when its module
-- loads, naming the field, instead of halfway through a load.
function Scenarios.define(def: Definition): Definition
	if type(def) ~= "table" then
		error("a scenario definition is a table", 2)
	end
	for key, value in pairs(def :: any) do
		local expected = DEFINITION_FIELDS[key]
		if key == "character" then
			if type(value) ~= "string" and type(value) ~= "table" then
				error(`scenario field 'character' must be a preset name, a spec table or "keep"`, 2)
			end
		elseif expected == nil then
			error(`unknown scenario field '{tostring(key)}'`, 2)
		elseif type(value) ~= expected then
			error(`scenario field '{key}' must be a {expected}, got {type(value)}`, 2)
		end
	end
	local known = DebugConfig.getAll()
	for _, field in ipairs({ "flags", "clientFlags" }) do
		for name, value in pairs((def :: any)[field] or {}) do
			if known[name] == nil or type(value) ~= "boolean" then
				error(`scenario {field}: '{tostring(name)}' is not a debug flag set to true or false`, 2)
			end
		end
	end
	return def
end

local function collectModules(folder: Instance, prefix: string, out: { { id: string, module: ModuleScript } })
	for _, child in ipairs(folder:GetChildren()) do
		local id = if prefix == "" then child.Name else `{prefix}/{child.Name}`
		if child:IsA("ModuleScript") then
			-- A module's own children are its helpers, not definitions.
			table.insert(out, { id = id, module = child })
		elseif child:IsA("Folder") then
			collectModules(child, id, out)
		end
	end
end

local function codeEntries(): { Entry }
	local entries: { Entry } = {}
	local defs = script:FindFirstChild("Defs")
	if not defs then
		return entries
	end
	local modules: { { id: string, module: ModuleScript } } = {}
	collectModules(defs, "", modules)
	for _, item in ipairs(modules) do
		local ok, value = pcall(require, item.module)
		local problem: string? = nil
		if not ok then
			problem = `{item.id} failed to load: {value}`
		else
			local checked, result = pcall(Scenarios.define, value)
			if checked then
				table.insert(entries, { id = item.id, source = "code", def = result })
			else
				problem = `{item.id}: {result}`
			end
		end
		if problem and not reported[problem] then
			reported[problem] = true
			warn(`[Scenarios] {problem}`)
		end
	end
	return entries
end

local function stageEntry(name: string): Entry?
	local container = game:GetService("ServerStorage"):FindFirstChild(Stages.CONTAINER_NAME)
	local model = container and container:FindFirstChild(name)
	if not model then
		return nil
	end
	local title = model:GetAttribute("Title")
	local description = model:GetAttribute("Description")
	local character = model:GetAttribute("Character")
	return {
		id = name,
		source = "stage",
		def = {
			title = if type(title) == "string" and title ~= "" then title else name,
			description = if type(description) == "string" then description else "",
			stage = name,
			character = if type(character) == "string" and character ~= "" then character else KEEP,
		},
	}
end

local function allEntries(): { Entry }
	local entries = codeEntries()
	local named: { [string]: boolean } = {}
	local ids: { [string]: boolean } = {}
	for _, entry in ipairs(entries) do
		ids[entry.id] = true
		if entry.def.stage then
			named[entry.def.stage] = true
		end
	end
	for _, name in ipairs(Stages.list()) do
		if not named[name] and not ids[name] then
			local entry = stageEntry(name)
			if entry then
				table.insert(entries, entry)
			end
		end
	end
	table.sort(entries, function(a, b)
		if (a.id == Scenarios.DEFAULT_ID) ~= (b.id == Scenarios.DEFAULT_ID) then
			return a.id == Scenarios.DEFAULT_ID
		end
		return a.id < b.id
	end)
	return entries
end

local function findEntry(id: string): Entry?
	for _, entry in ipairs(allEntries()) do
		if entry.id == id then
			return entry
		end
	end
	local lowered = string.lower(id)
	for _, entry in ipairs(allEntries()) do
		if string.lower(entry.id) == lowered then
			return entry
		end
	end
	return nil
end

local function characterLabel(character: any): string
	if character == nil then
		return KEEP
	end
	return if type(character) == "string" then character else "custom"
end

local function infoOf(entry: Entry): ScenarioInfo
	local def = entry.def
	return {
		id = entry.id,
		title = def.title or entry.id,
		description = def.description or "",
		stage = def.stage,
		character = characterLabel(def.character),
		source = entry.source,
		current = current ~= nil and (current :: Current).entry.id == entry.id,
	}
end

function Scenarios.list(): { ScenarioInfo }
	local infos: { ScenarioInfo } = {}
	for _, entry in ipairs(allEntries()) do
		table.insert(infos, infoOf(entry))
	end
	return infos
end

function Scenarios.ids(): { string }
	local ids: { string } = {}
	for _, entry in ipairs(allEntries()) do
		table.insert(ids, entry.id)
	end
	return ids
end

function Scenarios.current(): ScenarioInfo?
	local loaded = current
	return if loaded then infoOf(loaded.entry) else nil
end

-- Vector3s cross as { __vector3 = { x, y, z } } since JSON has no vector.
local function encodeTuneValue(value: any): any
	if typeof(value) == "Vector3" then
		return { __vector3 = { value.X, value.Y, value.Z } }
	end
	return value
end

local function bumpRevision()
	local folder = state
	if folder then
		folder:SetAttribute("Revision", ((folder:GetAttribute("Revision") :: number?) or 0) + 1)
	end
end

local function publish()
	local folder = state
	if not folder then
		return
	end
	local loaded = current
	local stage = Stages.current()
	folder:SetAttribute("ScenarioId", if loaded then loaded.entry.id else "")
	folder:SetAttribute("ScenarioTitle", if loaded then loaded.entry.def.title or loaded.entry.id else "")
	folder:SetAttribute("StageName", if stage then stage.name else "")
	local overrides = ""
	if loaded and (loaded.entry.def.clientFlags or loaded.entry.def.tune) then
		local tune: { [string]: any } = {}
		for path, value in pairs(loaded.entry.def.tune or {}) do
			tune[path] = encodeTuneValue(value)
		end
		overrides = HttpService:JSONEncode({ flags = loaded.entry.def.clientFlags or {}, tune = tune })
	end
	folder:SetAttribute("ClientOverrides", overrides)
	bumpRevision()
end

local function placeAll(cframe: CFrame)
	local players = Players:GetPlayers()
	local remaining = #players
	if remaining == 0 then
		return
	end
	local waiter = coroutine.running()
	for _, player in ipairs(players) do
		task.spawn(function()
			pcall(Stages.place, player, cframe)
			remaining -= 1
			if remaining == 0 and coroutine.status(waiter) == "suspended" then
				task.spawn(waiter)
			end
		end)
	end
	if remaining > 0 then
		coroutine.yield()
	end
end

local function teardown()
	local loaded = current
	if not loaded then
		return
	end
	current = nil
	Scope.close(loaded.handle)
end

local function newWorldFolder(): Folder
	local existing = Workspace:FindFirstChild(WORLD_FOLDER_NAME)
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = WORLD_FOLDER_NAME
	folder.Parent = Workspace
	return folder
end

local function spawnFromMarkers(handle: Scope.Handle, stage: Stages.Stage)
	for _, request in ipairs(stage:spawnRequests()) do
		local count = request.options.count
		count = if type(count) == "number" and count >= 1 then math.floor(count) else 1
		local options = table.clone(request.options)
		options.count = nil
		handle.scope.spawnRow(request.kind, count, request.cframe, { options = options })
	end
end

local loadEntry: (entry: Entry, player: Player?, fallback: boolean) -> (boolean, string?)

-- Runs one load step; on failure turns the error into "failed at <step>".
local function step(name: string, fn: () -> ()): string?
	local ok, err = xpcall(fn, function(message: any)
		if type(message) == "string" and not string.find(message, "\n") then
			return message
		end
		return debug.traceback(tostring(message), 2)
	end)
	return if ok then nil else `failed at {name}: {err}`
end

loadEntry = function(entry: Entry, player: Player?, fallback: boolean): (boolean, string?)
	local def = entry.def
	local handle: Scope.Handle? = nil

	local err = step("teardown", teardown)
		or step("stage", function()
			local stage: Stages.Stage? = nil
			if def.stage then
				local loaded, loadError = Stages.load(def.stage)
				if not loaded then
					error(loadError or "stage did not load", 0)
				end
				stage = loaded
			else
				Stages.unload()
			end
			local created = Scope.new({
				id = entry.id,
				player = player,
				stage = stage,
				folder = if stage then stage.folder else newWorldFolder(),
				ownsFolder = stage == nil,
				tag = Scenarios.SPAWN_TAG,
			})
			handle = created
			current = { entry = entry, handle = created, player = player }
		end)
		or step("spawn markers", function()
			local stage = Stages.current()
			if stage and handle then
				spawnFromMarkers(handle, stage)
			end
		end)
		or step("character", function()
			local character = def.character
			if character == nil or character == KEEP then
				return
			end
			if not player then
				warn(`[Scenarios] {entry.id}: no player to put the character on`)
				return
			end
			local ok, applyError = Characters.apply(player, character)
			if not ok then
				error(applyError or "character did not apply", 0)
			end
		end)
		or step("placing players", function()
			placeAll(Stages.start())
		end)
		or step("flags", function()
			if handle and def.flags then
				Scope.setFlags(handle, def.flags)
			end
		end)
		or step("setup", function()
			if handle and def.setup then
				def.setup(handle.scope)
			end
		end)

	if not err then
		publish()
		return true, nil
	end

	local message = `scenario '{entry.id}' {err}`
	warn(`[Scenarios] {message}`)
	teardown()
	local defaultEntry = findEntry(Scenarios.DEFAULT_ID)
	if fallback and entry.id ~= Scenarios.DEFAULT_ID and defaultEntry then
		local ok, defaultError = loadEntry(defaultEntry, player, false)
		message ..= if ok then "; loaded the default scenario instead" else `; the default scenario failed too ({defaultError})`
	else
		Stages.unload()
		pcall(placeAll, Stages.worldStart())
		publish()
		message ..= "; back in the baseplate world"
	end
	return false, message
end

local function remember(player: Player?, id: string)
	if player then
		task.spawn(Persistence.update, player.UserId, { last = id })
	end
end

local function unknown(id: string): string
	return `no scenario '{id}' ({table.concat(Scenarios.ids(), ", ")})`
end

-- Loads the scenario, putting its character (if any) on `player` (default: the first player).
-- Yields. False with the reason when it failed; the default scenario is loaded in its place.
function Scenarios.load(id: string, player: Player?): (boolean, string?)
	local entry = findEntry(id)
	if not entry then
		return false, unknown(id)
	end
	if busy then
		return false, "another scenario change is in progress"
	end
	busy = true
	booted = true
	local target = player or Players:GetPlayers()[1]
	local ok, result, message = pcall(loadEntry, entry, target, true)
	busy = false
	if not ok then
		return false, `loading '{entry.id}' crashed: {result}`
	end
	if result then
		remember(target, entry.id)
	end
	return result, message
end

-- Loads the current scenario again from scratch, for the same player.
function Scenarios.reload(): (boolean, string?)
	local loaded = current
	if not loaded then
		return false, "no scenario is loaded"
	end
	return Scenarios.load(loaded.entry.id, loaded.player)
end

-- Tears the scenario down, unloads its stage, puts every player back on their real save and at the
-- world spawn.
function Scenarios.exit(): (boolean, string?)
	if busy then
		return false, "another scenario change is in progress"
	end
	busy = true
	local problems: { string } = {}
	local ok, err = pcall(function()
		teardown()
		Stages.unload()
		for _, player in ipairs(Players:GetPlayers()) do
			local restored, restoreError = Characters.restore(player)
			if not restored then
				table.insert(problems, `{player.Name}: {restoreError}`)
			end
		end
		placeAll(Stages.worldStart())
	end)
	busy = false
	publish()
	if not ok then
		return false, `exit failed: {err}`
	end
	if #problems > 0 then
		return false, `left the scenario, but could not restore: {table.concat(problems, "; ")}`
	end
	return true, nil
end

-- What pressing Play loads for this player: "last" (the default), "default", or a scenario id.
function Scenarios.setBoot(player: Player, value: string): (boolean, string?)
	local lowered = string.lower(value)
	local stored: string
	if lowered == "last" or lowered == "default" then
		stored = lowered
	else
		local entry = findEntry(value)
		if not entry then
			return false, unknown(value)
		end
		stored = entry.id
	end
	if not Persistence.update(player.UserId, { boot = stored }) then
		return false, "the dev DataStore is not available; boot stays on the default scenario"
	end
	return true, stored
end

-- The scenario id pressing Play would load for this player. Yields.
function Scenarios.bootTarget(player: Player): (string, string)
	local prefs = Persistence.read(player.UserId)
	local pin = prefs.boot or "last"
	local id = if pin == "default" then Scenarios.DEFAULT_ID elseif pin == "last" then (prefs.last or Scenarios.DEFAULT_ID) else pin
	if not findEntry(id) then
		id = Scenarios.DEFAULT_ID
	end
	return id, pin
end

local function boot(player: Player)
	local id = Scenarios.bootTarget(player)
	local ok, err = Scenarios.load(id, player)
	if not ok then
		warn(`[Scenarios] boot scenario '{id}' did not load: {err}`)
	end
end

-- Spawns an NPC outside any definition (the `spawn` command): into the loaded scenario, so its
-- teardown removes it, or tagged loose when none is loaded.
function Scenarios.spawn(kind: string, cframe: CFrame, options: Spawning.Options?): (Model?, string?)
	local settings: Spawning.Options = { snapToGround = true }
	for key, value in pairs(options or {}) do
		settings[key] = value
	end
	local loaded = current
	if loaded then
		settings.parent = loaded.handle.scope.folder
		settings.tag = loaded.handle.tag
	else
		local stage = Stages.current()
		settings.parent = if stage then stage.folder else Workspace
		settings.tag = Scenarios.LOOSE_TAG
	end
	return Spawning.npc(kind, cframe, settings)
end

-- From the session-start hook, once the player's state is restored. The first player to arrive
-- boots the server into their boot scenario; later arrivals are placed at the loaded stage's start.
function Scenarios.onPlayerReady(player: Player)
	if not started then
		return
	end
	if not booted then
		booted = true
		task.spawn(boot, player)
		return
	end
	if Stages.current() then
		task.spawn(Stages.place, player, Stages.start())
	end
end

function Scenarios.start()
	if started or not DevAccess.isEnabled() then
		return
	end
	started = true

	local existing = ReplicatedStorage:FindFirstChild(STATE_NAME)
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Configuration")
	folder.Name = STATE_NAME
	folder:SetAttribute("ScenarioId", "")
	folder:SetAttribute("ScenarioTitle", "")
	folder:SetAttribute("StageName", "")
	folder:SetAttribute("ClientOverrides", "")
	folder:SetAttribute("Revision", 0)
	folder.Parent = ReplicatedStorage
	state = folder

	-- Stage commands change the stage outside a scenario load; the published name follows either way.
	Stages.onChanged(function(stage)
		local target = state
		if target and target:GetAttribute("StageName") ~= (if stage then stage.name else "") then
			target:SetAttribute("StageName", if stage then stage.name else "")
			bumpRevision()
		end
	end)
	Stages.prepareWorld()
end

return Scenarios
