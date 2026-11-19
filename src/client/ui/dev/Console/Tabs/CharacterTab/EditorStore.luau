--!strict
-- EditorStore: what the character editor shows and the edits it sends, outside React, apart from
-- ConsoleStore so the editor's frequent updates (live pools, polled state) re-render only the
-- Character tab, not the whole console.
--
-- The schema (every choice and limit) is read once. The state (the live build and its read-outs) is
-- read when the tab shows, every few seconds while it does, when the character's progression or
-- preset changes, and comes back with every edit. Pools are sampled from the replicated stats a few
-- times a second, so they follow a fight without asking the server.
--
-- An edit shows at once (an optimistic value under its path) and is sent as one `character set`
-- patch once edits settle; edits made while one is in flight are merged and sent after it. The
-- answer brings the server's state; a refused patch also brings its problems, and the optimistic
-- values drop away, so the controls snap back with the reason beside them.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local client = script:FindFirstAncestor("Client") :: Instance
local DevCommandsClient = require((client :: any).dev.Commands)
local StatsClient = require((client :: any).StatsClient)
local ProgressionClient = require((client :: any).Progression.ProgressionClient)
local ConsoleStore = require(script.Parent.Parent.Parent.ConsoleStore)

export type Problem = { field: string, message: string }

-- A refused edit: the paths it touched and why.
export type Failure = { paths: { string }, problems: { Problem }, message: string }

export type Pool = { current: number, max: number }

export type State = {
	schema: any?,
	schemaError: string?,
	state: any?,
	stateError: string?,
	optimistic: { [string]: any },
	failure: Failure?,
	-- The last answer of a command that is not a patch (hold, unlock, save...), shown in place.
	notice: { ok: boolean, message: string, key: string? }?,
	sending: boolean,
	pools: { [string]: Pool },
	sections: { [string]: boolean },
	view: string,
	-- Luau source shown by Copy source, and for which build.
	source: string?,
}

local EditorStore = {}

local STATE_POLL_SECONDS = 2.5
local POOL_SAMPLE_SECONDS = 0.2
local SETTLE_SECONDS = 0.3
local PROGRESSION_REFRESH_SECONDS = 1

local state: State = {
	schema = nil,
	schemaError = nil,
	state = nil,
	stateError = nil,
	optimistic = {},
	failure = nil,
	notice = nil,
	sending = false,
	pools = {},
	sections = { pools = true, mastery = true },
	view = "editor",
	source = nil,
}

local listeners: { [{}]: () -> () } = {}

local function emit()
	for _, listener in pairs(listeners) do
		task.spawn(listener)
	end
end

-- Stands for nil in a patch to `set`, since a nil value is no entry in a Luau table.
local NONE = table.freeze({})

local function set(patch: { [string]: any })
	local nextState = table.clone(state) :: any
	for key, value in pairs(patch) do
		nextState[key] = if value == NONE then nil else value
	end
	state = nextState
	emit()
end

function EditorStore.get(): State
	return state
end

function EditorStore.subscribe(callback: () -> ()): () -> ()
	local token = {}
	listeners[token] = callback
	return function()
		listeners[token] = nil
	end
end

-- Spec merge rules (dev/Characters/Types): maps merge key by key, anything else replaces.
local function isMap(value: any): boolean
	if type(value) ~= "table" or next(value) == nil then
		return false
	end
	for key in pairs(value) do
		if type(key) ~= "string" then
			return false
		end
	end
	return true
end

local function mergePatch(base: { [string]: any }, over: { [string]: any }): { [string]: any }
	local out = table.clone(base)
	for key, value in pairs(over) do
		if isMap(value) and isMap(out[key]) and value[1] == nil and value["1"] == nil then
			out[key] = mergePatch(out[key], value)
		else
			out[key] = value
		end
	end
	return out
end

local fetchingSchema = false
function EditorStore.ensureSchema()
	if state.schema or fetchingSchema then
		return
	end
	fetchingSchema = true
	task.spawn(function()
		local ok, result = pcall(DevCommandsClient.query, "character schema")
		fetchingSchema = false
		if ok and result.ok then
			set({ schema = result.data, schemaError = NONE })
		else
			set({ schemaError = if ok then result.message else tostring(result) })
		end
	end)
end

local fetchingState = false
local refetchState = false
function EditorStore.refresh()
	if fetchingState then
		refetchState = true
		return
	end
	fetchingState = true
	task.spawn(function()
		local ok, result = pcall(DevCommandsClient.query, "character state")
		fetchingState = false
		if ok and result.ok then
			set({ state = result.data, stateError = NONE })
		else
			set({ stateError = if ok then result.message else tostring(result) })
		end
		if refetchState then
			refetchState = false
			EditorStore.refresh()
		end
	end)
end

-- The value shown for `path`: the optimistic one while an edit is unconfirmed, else `fallback`.
function EditorStore.value(snapshot: State, path: string, fallback: any): any
	local value = snapshot.optimistic[path]
	if value == nil then
		return fallback
	end
	return value
end

-- Why the last refused edit failed, when it touched a path under one of `prefixes` or a problem is
-- about one of them; nil otherwise.
function EditorStore.errorFor(snapshot: State, prefixes: { string }): string?
	local failure = snapshot.failure
	if not failure then
		return nil
	end
	local function under(path: string): boolean
		for _, prefix in ipairs(prefixes) do
			if path == prefix or string.sub(path, 1, #prefix + 1) == prefix .. "." or string.sub(path, 1, #prefix + 1) == prefix .. "[" then
				return true
			end
		end
		return false
	end
	local messages: { string } = {}
	for _, problem in ipairs(failure.problems) do
		if under(problem.field) then
			table.insert(messages, problem.message)
		end
	end
	if #messages == 0 then
		for _, path in ipairs(failure.paths) do
			if under(path) then
				if #failure.problems > 0 then
					for _, problem in ipairs(failure.problems) do
						table.insert(messages, problem.message)
					end
				else
					table.insert(messages, failure.message)
				end
				break
			end
		end
	end
	return if #messages > 0 then table.concat(messages, "\n") else nil
end

-- Whether a problem names exactly `path` (to outline one control rather than a whole section).
function EditorStore.isInvalid(snapshot: State, path: string): boolean
	local failure = snapshot.failure
	if not failure then
		return false
	end
	for _, problem in ipairs(failure.problems) do
		if problem.field == path then
			return true
		end
	end
	return false
end

-- Pending edits: merged into one patch, sent once they settle.
local pending: { [string]: any }? = nil
local pendingPaths: { string } = {}
local versions: { [string]: number } = {}
local inflight = false
local settleToken = 0

local send: () -> ()

local function schedule(delay: number)
	settleToken += 1
	local token = settleToken
	task.delay(delay, function()
		if token == settleToken and not inflight and pending then
			send()
		end
	end)
end

local function applyAnswer(result: any, sentPaths: { string }, sentVersions: { [string]: number })
	local patch: { [string]: any } = { sending = false }
	local data = result.data
	if type(data) == "table" and type(data.state) == "table" then
		patch.state = data.state
	end
	local optimistic = table.clone(state.optimistic)
	for _, path in ipairs(sentPaths) do
		if versions[path] == sentVersions[path] then
			optimistic[path] = nil
		end
	end
	patch.optimistic = optimistic
	if result.ok then
		patch.failure = NONE
	else
		patch.failure = {
			paths = sentPaths,
			problems = if type(data) == "table" and type(data.problems) == "table" then data.problems else {},
			message = result.message,
		}
	end
	set(patch)
	if not patch.state then
		EditorStore.refresh()
	end
end

send = function()
	local patch = pending
	if not patch then
		return
	end
	local paths = pendingPaths
	pending = nil
	pendingPaths = {}
	local sentVersions: { [string]: number } = {}
	for _, path in ipairs(paths) do
		sentVersions[path] = versions[path]
	end
	inflight = true
	set({ sending = true })
	ConsoleStore.run(`character set {HttpService:JSONEncode(patch)}`, {
		done = function(result)
			inflight = false
			applyAnswer(result, paths, sentVersions)
			if pending then
				schedule(0)
			end
		end,
	})
end

-- One edit: shows `value` under `path` at once and queues `patch` (a partial spec).
function EditorStore.edit(path: string, value: any, patch: { [string]: any }, immediate: boolean?)
	versions[path] = (versions[path] or 0) + 1
	local optimistic = table.clone(state.optimistic)
	optimistic[path] = value
	pending = mergePatch(pending or {}, patch)
	if not table.find(pendingPaths, path) then
		table.insert(pendingPaths, path)
	end
	set({ optimistic = optimistic })
	schedule(if immediate then 0 else SETTLE_SECONDS)
end

-- A command that is not a patch (apply, restore, revert, hold, unlock, save, delete). The state is
-- read again afterwards unless the answer carries it; `done` sees the answer.
function EditorStore.command(text: string, key: string?, done: ((any) -> ())?)
	ConsoleStore.run(text, {
		key = if key then "character:" .. key else nil,
		refresh = { "presets" },
		done = function(result)
			local data = result.data
			local patch: { [string]: any } = { notice = { ok = result.ok, message = result.message, key = key } }
			if type(data) == "table" and type(data.state) == "table" then
				patch.state = data.state
			end
			if result.ok then
				patch.failure = NONE
			end
			set(patch)
			if not patch.state then
				EditorStore.refresh()
			end
			if done then
				done(result)
			end
		end,
	})
end

function EditorStore.clearNotice()
	if state.notice then
		set({ notice = NONE })
	end
end

function EditorStore.setSection(id: string, open: boolean)
	local sections = table.clone(state.sections)
	sections[id] = open
	set({ sections = sections })
end

function EditorStore.setView(view: string)
	if state.view ~= view then
		set({ view = view })
	end
end

function EditorStore.setSource(source: string?)
	set({ source = if source == nil then NONE else source })
end

local function samplePools()
	local schema = state.schema
	if not schema then
		return
	end
	local pools: { [string]: Pool } = {}
	local changed = false
	for _, name in ipairs(schema.pools) do
		local pool = StatsClient.getPool(name)
		if pool and pool.current and pool.max then
			local entry = { current = pool.current, max = pool.max }
			local previous = state.pools[name]
			if not previous or math.abs(previous.current - entry.current) >= 0.5 or previous.max ~= entry.max then
				changed = true
			end
			pools[name] = entry
		end
	end
	if changed then
		set({ pools = pools })
	end
end

-- Keeps the state and pools current while the editor is on screen; the returned function stops it.
function EditorStore.live(): () -> ()
	local running = true
	EditorStore.ensureSchema()
	EditorStore.refresh()
	task.spawn(function()
		local sinceState = 0
		while running do
			task.wait(POOL_SAMPLE_SECONDS)
			if not running then
				break
			end
			samplePools()
			sinceState += POOL_SAMPLE_SECONDS
			if sinceState >= STATE_POLL_SECONDS then
				sinceState = 0
				if not inflight then
					EditorStore.refresh()
				end
			end
		end
	end)
	local lastProgression = 0
	local stopProgression = ProgressionClient.onChanged(function()
		local now = os.clock()
		if now - lastProgression >= PROGRESSION_REFRESH_SECONDS then
			lastProgression = now
			task.delay(0.2, EditorStore.refresh)
		end
	end)
	local player = Players.LocalPlayer
	local characterChanged = player:GetAttributeChangedSignal("DevCharacter"):Connect(function()
		set({ failure = NONE, optimistic = {}, source = NONE })
		EditorStore.refresh()
	end)
	return function()
		running = false
		stopProgression()
		characterChanged:Disconnect()
	end
end

return EditorStore
