--!strict
-- ScenarioOverrides: puts the loaded scenario's client debug flags and tuning overrides into effect,
-- and takes them back out when the scenario changes.
--
-- The server publishes them as JSON in ReplicatedStorage.DevState's ClientOverrides attribute
-- (empty when there are none). The value each flag and tuning path had before the scenario changed
-- it is remembered here, so leaving the scenario restores exactly that -- including a tuning path
-- that had no override, which is reset rather than set to its default.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugConfig = require(ReplicatedStorage.Shared.Debug.DebugConfig)
local DevTuningService = require(script.Parent.DevTuningService)

local ScenarioOverrides = {}

local STATE_WAIT_SECONDS = 30

type Applied = {
	flags: { [string]: boolean },
	-- Path -> { value = the override before, or nil when there was none }.
	tune: { [string]: { value: any } },
}

local applied: Applied = { flags = {}, tune = {} }
local started = false

local function decodeTuneValue(value: any): any
	if type(value) == "table" and type(value.__vector3) == "table" then
		local v = value.__vector3
		return Vector3.new(tonumber(v[1]) or 0, tonumber(v[2]) or 0, tonumber(v[3]) or 0)
	end
	return value
end

local function revert()
	for name, value in pairs(applied.flags) do
		DebugConfig.set(name, value)
	end
	for path, before in pairs(applied.tune) do
		if before.value == nil then
			DevTuningService.reset(path)
		else
			DevTuningService.set(path, before.value)
		end
	end
	applied = { flags = {}, tune = {} }
end

local function apply(json: string)
	revert()
	if json == "" then
		return
	end
	local ok, decoded = pcall(HttpService.JSONDecode, HttpService, json)
	if not ok or type(decoded) ~= "table" then
		warn(`[ScenarioOverrides] unreadable overrides: {tostring(decoded)}`)
		return
	end
	local current = DebugConfig.getAll()
	for name, value in pairs(decoded.flags or {}) do
		if type(name) == "string" and type(value) == "boolean" then
			applied.flags[name] = current[name] == true
			DebugConfig.set(name, value)
		end
	end
	for path, value in pairs(decoded.tune or {}) do
		if type(path) == "string" then
			applied.tune[path] = { value = DevTuningService.getOverride(path) }
			DevTuningService.set(path, decodeTuneValue(value))
		end
	end
end

function ScenarioOverrides.start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		local state = ReplicatedStorage:WaitForChild("DevState", STATE_WAIT_SECONDS)
		if not state then
			return
		end
		local function refresh()
			local value = state:GetAttribute("ClientOverrides")
			apply(if type(value) == "string" then value else "")
		end
		state:GetAttributeChangedSignal("ClientOverrides"):Connect(refresh)
		refresh()
	end)
end

return ScenarioOverrides
