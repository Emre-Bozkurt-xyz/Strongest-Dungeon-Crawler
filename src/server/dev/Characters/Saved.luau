--!strict
-- Saved presets: characters captured in play and kept between Play sessions in a DataStore of their
-- own (never the player save), so a build made in the editor outlives the server it was made on.
--
-- One key holds every saved preset for the place, as specs in JSON-safe form (Serialize.toData):
-- presets are shared tooling, not one developer's. Reads happen once when dev tooling starts; each
-- save or delete is an UpdateAsync of that key, so two Studio sessions saving at once do not drop
-- each other's presets.
--
-- Best effort, like scenario persistence. When the store cannot be read (an unpublished place, API
-- access off, an outage), presets are kept for the session only and every result says so.

local DataStoreService = game:GetService("DataStoreService")

local Serialize = require(script.Parent.Serialize)

local STORE_NAME = "DevCharacterPresets"
local KEY = "presets"
local READ_TIMEOUT = 6

-- `persisted` is false for a preset kept for this session only.
export type Entry = { spec: any, savedAt: number, persisted: boolean }

local Saved = {}

local presets: { [string]: Entry } = {}
local loaded = false
-- Why the store is unusable, or nil while it works. Set by a failed read or write.
local unavailable: string? = nil
local loadWaiters: { thread } = {}

local function store(): (DataStore?, string?)
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		return result, nil
	end
	return nil, tostring(result)
end

local function decode(value: any): { [string]: Entry }
	local out: { [string]: Entry } = {}
	local stored = if type(value) == "table" then value.presets else nil
	if type(stored) ~= "table" then
		return out
	end
	for name, entry in pairs(stored) do
		if type(name) == "string" and type(entry) == "table" and type(entry.spec) == "table" then
			out[name] = { spec = Serialize.fromData(entry.spec), savedAt = tonumber(entry.savedAt) or 0, persisted = true }
		end
	end
	return out
end

local function finishLoad()
	loaded = true
	local waiters = loadWaiters
	loadWaiters = {}
	for _, thread in ipairs(waiters) do
		task.spawn(thread)
	end
end

-- Reads every saved preset. Called once at start; never yields the caller.
function Saved.load()
	task.spawn(function()
		local dataStore, err = store()
		if not dataStore then
			unavailable = err or "no DataStore"
			finishLoad()
			return
		end
		local done = false
		task.delay(READ_TIMEOUT, function()
			if not done then
				done = true
				unavailable = "the preset store did not answer in time"
				finishLoad()
			end
		end)
		local ok, value = pcall(function()
			return dataStore:GetAsync(KEY)
		end)
		if done then
			return
		end
		done = true
		if ok then
			presets = decode(value)
		else
			unavailable = tostring(value)
		end
		finishLoad()
	end)
end

-- Yields until the first read has finished (or `timeout` seconds pass), so a scenario that boots
-- on a saved preset finds it.
function Saved.awaitLoaded(timeout: number)
	if loaded then
		return
	end
	local thread = coroutine.running()
	table.insert(loadWaiters, thread)
	task.delay(timeout, function()
		local index = table.find(loadWaiters, thread)
		if index then
			table.remove(loadWaiters, index)
			task.spawn(thread)
		end
	end)
	coroutine.yield()
end

function Saved.isLoaded(): boolean
	return loaded
end

-- Nil while presets persist; else why they are kept for this session only.
function Saved.unavailableReason(): string?
	return unavailable
end

function Saved.get(name: string): any?
	local entry = presets[name]
	return entry and entry.spec
end

-- "saved" when it is in the store, "session" when it is kept for this session only, nil for neither.
function Saved.source(name: string): string?
	local entry = presets[name]
	if not entry then
		return nil
	end
	return if entry.persisted then "saved" else "session"
end

function Saved.names(): { string }
	local names: { string } = {}
	for name in pairs(presets) do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

local function write(transform: (stored: { [string]: any }) -> ()): (boolean, string?)
	local dataStore, err = store()
	if not dataStore then
		return false, err
	end
	local ok, result = pcall(function()
		return dataStore:UpdateAsync(KEY, function(value: any)
			local root = if type(value) == "table" then value else {}
			local stored = if type(root.presets) == "table" then root.presets else {}
			transform(stored)
			root.presets = stored
			return root
		end)
	end)
	if not ok then
		return false, tostring(result)
	end
	return true, nil
end

-- Keeps `spec` under `name`: in the store when it works, else for this session. Returns whether it
-- persisted, and why not when it did not.
function Saved.put(name: string, spec: any): (boolean, string?)
	local entry: Entry = { spec = spec, savedAt = os.time(), persisted = false }
	presets[name] = entry
	if unavailable then
		return false, unavailable
	end
	local data = Serialize.toData(spec)
	local ok, err = write(function(stored)
		stored[name] = { spec = data, savedAt = entry.savedAt }
	end)
	if ok then
		entry.persisted = true
	else
		unavailable = err
	end
	return ok, err
end

-- Forgets `name` here and in the store. False when there was no such preset.
function Saved.remove(name: string): (boolean, string?)
	local entry = presets[name]
	if not entry then
		return false, nil
	end
	presets[name] = nil
	if not entry.persisted then
		return true, nil
	end
	if unavailable then
		return true, unavailable
	end
	local ok, err = write(function(stored)
		stored[name] = nil
	end)
	if not ok then
		unavailable = err
		return true, err
	end
	return true, nil
end

return Saved
