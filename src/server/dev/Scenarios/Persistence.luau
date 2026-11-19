--!strict
-- Persistence: each developer's scenario preferences, kept between Play sessions in a DataStore of
-- its own (never the player save): the scenario they last loaded and what pressing Play should load.
--
-- Everything here is best effort. Without DataStore access (an unpublished place, API access off,
-- an outage) reads give nothing and writes are dropped, so a session simply starts in the default
-- scenario; nothing waits on the store for longer than READ_TIMEOUT.

local DataStoreService = game:GetService("DataStoreService")

export type Prefs = {
	-- Id of the scenario last loaded successfully.
	last: string?,
	-- "last" (the default), "default", or a scenario id.
	boot: string?,
}

local STORE_NAME = "DevScenarios"
local READ_TIMEOUT = 4

local Persistence = {}

-- What this server last read or wrote per user, so an unchanged value is not written again.
local cache: { [number]: Prefs } = {}
local warnedWrite = false

local function keyFor(userId: number): string
	return `u{userId}`
end

local function store(): DataStore?
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	return if ok then result else nil
end

local function sanitize(value: any): Prefs
	local prefs: Prefs = {}
	if type(value) == "table" then
		if type(value.last) == "string" then
			prefs.last = value.last
		end
		if type(value.boot) == "string" then
			prefs.boot = value.boot
		end
	end
	return prefs
end

-- The user's preferences, or empty ones when the store cannot be read in time. Yields.
function Persistence.read(userId: number): Prefs
	local dataStore = store()
	if not dataStore then
		return {}
	end
	local result: Prefs? = nil
	local done = false
	local reader = coroutine.running()
	-- Whichever of the read and the timeout finishes first wakes the reader; the other finds it no
	-- longer waiting.
	local waiting = false
	local function wake()
		if waiting then
			waiting = false
			task.spawn(reader)
		end
	end
	task.spawn(function()
		local ok, value = pcall(function()
			return dataStore:GetAsync(keyFor(userId))
		end)
		if ok then
			result = sanitize(value)
		end
		done = true
		wake()
	end)
	if not done then
		waiting = true
		task.delay(READ_TIMEOUT, wake)
		coroutine.yield()
	end
	local prefs = result or {}
	cache[userId] = table.clone(prefs)
	return prefs
end

-- Merges `changes` into the user's preferences. Yields; false when the store could not be written.
function Persistence.update(userId: number, changes: Prefs): boolean
	local known = cache[userId]
	if known and (changes.last == nil or changes.last == known.last) and (changes.boot == nil or changes.boot == known.boot) then
		return true
	end
	local dataStore = store()
	if not dataStore then
		return false
	end
	local ok, err = pcall(function()
		dataStore:UpdateAsync(keyFor(userId), function(old: any)
			local prefs = sanitize(old)
			if changes.last ~= nil then
				prefs.last = changes.last
			end
			if changes.boot ~= nil then
				prefs.boot = changes.boot
			end
			cache[userId] = table.clone(prefs)
			return prefs
		end)
	end)
	if not ok and not warnedWrite then
		warnedWrite = true
		warn(`[Scenarios] could not save scenario preferences ({err}); boot falls back to the default scenario`)
	end
	return ok
end

return Persistence
