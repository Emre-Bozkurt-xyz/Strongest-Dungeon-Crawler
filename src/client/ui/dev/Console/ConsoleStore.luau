--!strict
-- ConsoleStore: everything the dev console shows and every request it makes, outside React.
--
-- Kept in a module rather than component state so the console comes back as it was after a respawn
-- or a remount: open or closed, the tab, the history, the last lists. Components read a snapshot
-- through `useConsole` and call the functions here; nothing in a render path ever yields.
--
-- Every action goes through DevCommandsClient.run (logged, shown in the command line's result
-- strip). Lists are read with DevCommandsClient.query, which does not log, so refreshing a list never
-- buries what the developer actually ran. A list is fetched when the console opens, after an action
-- that changes it, and when the replicated dev state says the world changed (DevState.Revision, the
-- player's DevCharacter attribute).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local client = script:FindFirstAncestor("Client") :: Instance
local DevCommandsClient = require((client :: any).dev.Commands)

export type Result = { ok: boolean, message: string, data: any? }

export type LastResult = {
	text: string,
	ok: boolean,
	message: string,
	time: number,
}

export type DevState = {
	scenarioId: string,
	scenarioTitle: string,
	stageName: string,
	revision: number,
}

export type ListName = "scenarios" | "boot" | "presets" | "stages" | "markers" | "npcs" | "flags" | "cflags"

export type State = {
	open: boolean,
	tab: string,
	descriptors: { any },
	-- Raw `data` of each list's last successful read; nil until read.
	lists: { [string]: any },
	-- A list whose last read failed, with why.
	listErrors: { [string]: string },
	-- Action keys with a request in flight.
	busy: { [string]: boolean },
	-- The last result of each keyed action, for actions whose answer is shown in place.
	results: { [string]: Result },
	last: LastResult?,
	devState: DevState,
	devCharacter: string,
	-- Whether the character editor has changed the build since its preset was applied.
	devCharacterEdited: boolean,
	-- The NPC picked in the World tab, for Inspect.
	inspectTarget: string?,
	-- Client errors and warnings logged while the console was closed.
	unread: number,
	-- Recent client errors and warnings, oldest first.
	output: { OutputEntry },
	-- Which list the Log tab shows: "commands" or "output".
	logView: string,
	-- The row picked in each tab, by the key the tab gave it. A tab falls back to a default of its
	-- own when this is unset or names a row that is gone.
	selection: { [string]: string },
	-- What Enter on an empty command line would do in each tab, shown there as ghost text.
	ghosts: { [string]: Ghost },
}

export type Ghost = { label: string, command: string }

-- What a tab offers the command line: its selectable rows in order, which is picked, and the picked
-- row's primary action. `command` is run as is; `run` replaces that when the action is not a single
-- command; `fill` is put on the line for completing by hand when the action cannot run yet.
export type Primary = {
	label: string,
	command: string?,
	options: RunOptions?,
	run: (() -> ())?,
	enabled: boolean?,
	fill: string?,
}

export type View = {
	keys: { string },
	selected: string?,
	primary: Primary?,
	-- Replaces the plain selection change, for a tab whose selection lives elsewhere (Inspect's
	-- target).
	onSelect: ((string) -> ())?,
}

export type OutputEntry = {
	message: string,
	isError: boolean,
	time: number,
}

local ConsoleStore = {}

ConsoleStore.TABS = { "scenarios", "character", "world", "debug", "commands", "log", "inspect" }

local LIST_COMMANDS: { [string]: string } = {
	scenarios = "scenario list",
	boot = "scenario boot",
	presets = "character list",
	stages = "stage list",
	markers = "markers",
	npcs = "npcs",
	flags = "flags",
	cflags = "cflags",
}

local HISTORY_LIMIT = 100

local state: State = {
	open = false,
	tab = "scenarios",
	descriptors = {},
	lists = {},
	listErrors = {},
	busy = {},
	results = {},
	last = nil,
	devState = { scenarioId = "", scenarioTitle = "", stageName = "", revision = 0 },
	devCharacter = "",
	devCharacterEdited = false,
	inspectTarget = nil,
	unread = 0,
	output = {},
	logView = "commands",
	selection = {},
	ghosts = {},
}

-- Each tab's last published view. Read only on a key press, so it is kept out of the state and
-- publishing it re-renders nothing unless the ghost text changes.
local views: { [string]: View } = {}
local focusInput: (() -> ())? = nil

local OUTPUT_LIMIT = 100

-- Oldest first; the command line walks it from the end.
local history: { string } = {}
local listeners: { [{}]: () -> () } = {}
local fetching: { [string]: boolean } = {}
-- A list asked for again while its read is in flight is read once more when that read lands, so a
-- refresh triggered mid-request is never lost.
local refetch: { [string]: boolean } = {}
local started = false

local function emit()
	for _, listener in pairs(listeners) do
		task.spawn(listener)
	end
end

-- Replaces the top-level fields in `patch`. Nested tables are swapped, never edited in place, so a
-- snapshot a component holds never changes under it.
local function set(patch: { [string]: any })
	local nextState = table.clone(state) :: any
	for key, value in pairs(patch) do
		nextState[key] = value
	end
	state = nextState
	emit()
end

local function setIn(field: string, key: string, value: any)
	local copy = table.clone((state :: any)[field])
	copy[key] = value
	set({ [field] = copy })
end

function ConsoleStore.get(): State
	return state
end

function ConsoleStore.subscribe(callback: () -> ()): () -> ()
	local token = {}
	listeners[token] = callback
	return function()
		listeners[token] = nil
	end
end

function ConsoleStore.history(): { string }
	return history
end

local function remember(text: string)
	if history[#history] ~= text then
		table.insert(history, text)
		if #history > HISTORY_LIMIT then
			table.remove(history, 1)
		end
	end
end

-- Reads one list in the background. Safe to call at any rate: concurrent reads of a list collapse
-- into one plus a trailing re-read.
function ConsoleStore.fetch(name: ListName)
	local command = LIST_COMMANDS[name]
	if not command then
		return
	end
	if fetching[name] then
		refetch[name] = true
		return
	end
	fetching[name] = true
	task.spawn(function()
		local ok, result = pcall(DevCommandsClient.query, command)
		fetching[name] = nil
		if ok and result.ok then
			setIn("lists", name, result.data or {})
			if state.listErrors[name] then
				setIn("listErrors", name, nil)
			end
		else
			setIn("listErrors", name, if ok then result.message else tostring(result))
		end
		if refetch[name] then
			refetch[name] = nil
			ConsoleStore.fetch(name)
		end
	end)
end

function ConsoleStore.fetchMany(names: { ListName })
	for _, name in ipairs(names) do
		ConsoleStore.fetch(name)
	end
end

-- Descriptors carry live choice lists (presets, stages, NPC kinds), so they are fetched again each
-- time the console opens.
function ConsoleStore.refreshDescriptors()
	if fetching.descriptors then
		return
	end
	fetching.descriptors = true
	task.spawn(function()
		local ok, descriptors = pcall(DevCommandsClient.refresh)
		fetching.descriptors = nil
		if ok and type(descriptors) == "table" then
			set({ descriptors = descriptors })
		end
	end)
end

export type RunOptions = {
	-- Marks the action busy under this key, and keeps its result under it.
	key: string?,
	-- Lists to read again once the command has finished, whatever its outcome.
	refresh: { ListName }?,
	-- Called with the result once it is back.
	done: ((Result) -> ())?,
	-- Typed by the developer, so it goes into the command line's history.
	typed: boolean?,
}

-- Runs a command line on a fresh thread and returns at once. An action already running under the
-- same key is not started twice.
function ConsoleStore.run(text: string, options: RunOptions?)
	local opts: RunOptions = options or {}
	local key = opts.key
	if key and state.busy[key] then
		return
	end
	if opts.typed then
		remember(text)
	end
	if key then
		setIn("busy", key, true)
	end
	task.spawn(function()
		local ok, result = pcall(DevCommandsClient.run, text)
		local outcome: Result = if ok then result else { ok = false, message = tostring(result) }
		local patch: { [string]: any } = {
			last = { text = text, ok = outcome.ok, message = outcome.message, time = os.clock() },
		}
		if key then
			local busy = table.clone(state.busy)
			busy[key] = nil
			local results = table.clone(state.results)
			results[key] = outcome
			patch.busy = busy
			patch.results = results
		end
		set(patch)
		for _, name in ipairs(opts.refresh or {}) do
			ConsoleStore.fetch(name)
		end
		if opts.done then
			task.spawn(opts.done, outcome)
		end
	end)
end

-- Whether any action whose key starts with `prefix` is in flight, for groups of actions that must not
-- overlap (two scenario loads, two character swaps).
function ConsoleStore.anyBusy(snapshot: State, prefix: string): boolean
	for key in pairs(snapshot.busy) do
		if string.sub(key, 1, #prefix) == prefix then
			return true
		end
	end
	return false
end

function ConsoleStore.clearResult(key: string)
	if state.results[key] then
		setIn("results", key, nil)
	end
end

function ConsoleStore.setTab(tab: string)
	if state.tab ~= tab then
		set({ tab = tab })
	end
end

function ConsoleStore.setInspectTarget(target: string?)
	set({ inspectTarget = target })
end

function ConsoleStore.select(tab: string, key: string?)
	if state.selection[tab] ~= key then
		setIn("selection", tab, key)
	end
end

-- Called by a tab on every render with what it shows. Only a change of the ghost text is state.
function ConsoleStore.publishView(tab: string, view: View)
	views[tab] = view
	local primary = view.primary
	local text = if primary then primary.command or primary.fill else nil
	local ghost: Ghost? = if primary and text then { label = primary.label, command = text } else nil
	local current = state.ghosts[tab]
	local same = if ghost and current then ghost.label == current.label and ghost.command == current.command else ghost == current
	if not same then
		setIn("ghosts", tab, ghost)
	end
end

-- Moves the active tab's selection by `delta` rows, stopping at either end. False when the tab has
-- no rows to move through.
function ConsoleStore.moveSelection(delta: number): boolean
	local tab = state.tab
	local view = views[tab]
	if not view or #view.keys == 0 then
		return false
	end
	local index = if view.selected then table.find(view.keys, view.selected) else nil
	local nextIndex = if index then math.clamp(index + delta, 1, #view.keys) else (if delta > 0 then 1 else #view.keys)
	local key = view.keys[nextIndex]
	if view.onSelect then
		view.onSelect(key)
	else
		ConsoleStore.select(tab, key)
	end
	return true
end

-- Runs the active tab's primary action for its selected row. When there is one but it cannot run
-- yet, returns the text to put on the command line instead, so it can be finished by hand.
function ConsoleStore.runPrimary(): (boolean, string?)
	local view = views[state.tab]
	local primary = view and view.primary
	if not primary then
		return false, nil
	end
	if primary.enabled == false or not (primary.run or primary.command) then
		return false, primary.fill
	end
	if primary.run then
		primary.run()
	elseif primary.command then
		ConsoleStore.run(primary.command, primary.options)
	end
	return true, nil
end

-- The command line registers how to take focus, so clicking a row can hand the keyboard back to it
-- (Up/Down and Enter act on the selection from there).
function ConsoleStore.setFocuser(callback: (() -> ())?)
	focusInput = callback
end

function ConsoleStore.focusInput()
	if focusInput then
		focusInput()
	end
end

-- Picks a row from a click: selects it and gives the keyboard to the command line.
function ConsoleStore.pick(tab: string, key: string)
	ConsoleStore.select(tab, key)
	ConsoleStore.focusInput()
end

local pendingOutput: { OutputEntry } = {}
local outputFlushScheduled = false

-- A client warning or error from the output: kept for the Log tab, and counted as unread while the
-- console is closed. Applied in batches a few times a second, so a burst of warnings is one render,
-- and a warning raised while rendering cannot feed back into an immediate re-render.
function ConsoleStore.pushOutput(message: string, isError: boolean)
	table.insert(pendingOutput, { message = message, isError = isError, time = os.time() })
	if outputFlushScheduled then
		return
	end
	outputFlushScheduled = true
	task.delay(0.25, function()
		outputFlushScheduled = false
		local output = table.clone(state.output)
		for _, entry in ipairs(pendingOutput) do
			table.insert(output, entry)
		end
		local added = #pendingOutput
		table.clear(pendingOutput)
		while #output > OUTPUT_LIMIT do
			table.remove(output, 1)
		end
		set({ output = output, unread = if state.open then state.unread else state.unread + added })
	end)
end

function ConsoleStore.clearOutput()
	set({ output = {}, unread = 0 })
end

function ConsoleStore.setLogView(view: string)
	if state.logView ~= view then
		set({ logView = view })
	end
end

local ALL_LISTS: { ListName } = { "scenarios", "boot", "presets", "stages", "markers", "npcs", "flags", "cflags" }
ConsoleStore.ALL_LISTS = ALL_LISTS

function ConsoleStore.setOpen(open: boolean)
	if state.open == open then
		return
	end
	set({ open = open, unread = if open then 0 else state.unread })
	if open then
		ConsoleStore.refreshDescriptors()
		ConsoleStore.fetchMany(ALL_LISTS)
	end
end

function ConsoleStore.toggle()
	ConsoleStore.setOpen(not state.open)
end

-- The descriptor for a command name, or nil.
function ConsoleStore.descriptor(name: string): any?
	for _, descriptor in ipairs(state.descriptors) do
		if descriptor.name == name then
			return descriptor
		end
	end
	return nil
end

-- The live choices of one argument of one command, as the descriptors last reported them.
function ConsoleStore.choices(command: string, argName: string): { string }
	local descriptor = ConsoleStore.descriptor(command)
	for _, arg in ipairs(descriptor and descriptor.args or {}) do
		if arg.name == argName then
			return arg.choices or {}
		end
	end
	return {}
end

local function readDevState(folder: Instance): DevState
	local function text(name: string): string
		local value = folder:GetAttribute(name)
		return if type(value) == "string" then value else ""
	end
	local revision = folder:GetAttribute("Revision")
	return {
		scenarioId = text("ScenarioId"),
		scenarioTitle = text("ScenarioTitle"),
		stageName = text("StageName"),
		revision = if type(revision) == "number" then revision else 0,
	}
end

-- Follows the replicated dev state for the header and re-reads what a world change invalidates.
-- The scenario list carries `current`, the stage list and markers follow the stage, and a scenario
-- change replaces the NPCs and may set flags.
function ConsoleStore.start()
	if started then
		return
	end
	started = true

	task.spawn(function()
		local folder = ReplicatedStorage:WaitForChild("DevState", math.huge)
		local function sync()
			local previous = state.devState.revision
			local devState = readDevState(folder)
			set({ devState = devState })
			if state.open and devState.revision ~= previous then
				ConsoleStore.fetchMany({ "scenarios", "stages", "markers", "npcs", "flags", "cflags" })
				-- The server remembers the last scenario in the background after a load; read the boot
				-- target once that has had time to land.
				task.delay(1.5, ConsoleStore.fetch, "boot")
			end
		end
		folder.AttributeChanged:Connect(sync)
		sync()
	end)

	local player = Players.LocalPlayer
	local function syncCharacter()
		local value = player:GetAttribute("DevCharacter")
		set({
			devCharacter = if type(value) == "string" then value else "",
			devCharacterEdited = player:GetAttribute("DevCharacterEdited") == true,
		})
		if state.open then
			ConsoleStore.fetch("presets")
		end
	end
	player:GetAttributeChangedSignal("DevCharacter"):Connect(syncCharacter)
	player:GetAttributeChangedSignal("DevCharacterEdited"):Connect(syncCharacter)
	syncCharacter()
end

return ConsoleStore
