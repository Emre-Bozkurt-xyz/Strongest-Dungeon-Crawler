--!strict
-- ExecutionClient: Mirrors execution lock state from server
-- Tracks which skill is currently executing to prevent spam and validate combo chaining

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Networking = require(ReplicatedStorage.Shared.Networking)

local EVENT_NAME = "ExecutionStateUpdate"
local EXECUTION_CHANNEL_NAME = "Skills" -- Uses same channel as skill events

local dispatcher = Networking.client()
local dispatcherAny = dispatcher :: any
dispatcherAny:_ensureChannel(EXECUTION_CHANNEL_NAME)

local ExecutionClient = {}

-- Current execution state
local executionState = {
	isLocked = false,
	lockedSkill = nil :: string?,
}

local listeners: { (boolean, string?) -> () } = {}

local function fire(locked: boolean, skillName: string?)
	for _, cb in ipairs(listeners) do
		pcall(cb, locked, skillName)
	end
end

-- Check if any skill is currently executing
function ExecutionClient.isLocked(): boolean
	return executionState.isLocked
end

-- Get the name of the skill that's currently executing (if any)
function ExecutionClient.getLockedSkill(): string?
	if not executionState.isLocked then
		return nil
	end
	return executionState.lockedSkill
end

-- Check if a specific skill is locked
function ExecutionClient.isSkillLocked(skillName: string): boolean
	if not executionState.isLocked then
		return false
	end
	return executionState.lockedSkill == skillName
end

-- Listen to execution state changes
function ExecutionClient.onChanged(callback: (boolean, string?) -> ()): () -> ()
	table.insert(listeners, callback)
	return function()
		for i, cb in ipairs(listeners) do
			if cb == callback then
				table.remove(listeners, i)
				break
			end
		end
	end
end

-- Internal: Update state from server event
local function updateState(locked: boolean, skillName: string?)
	local changed = executionState.isLocked ~= locked or executionState.lockedSkill ~= skillName
	
	executionState.isLocked = locked
	executionState.lockedSkill = skillName
	
	if changed then
		fire(locked, skillName)
	end
end

-- Listen to server execution state updates
dispatcherAny:on(EVENT_NAME, function(payload: any, _meta: any?)
	if type(payload) ~= "table" then
		return
	end
	
	local locked = payload.locked
	local skillName = payload.skillName
	
	if type(locked) == "boolean" then
		updateState(locked, skillName)
	end
end)

return ExecutionClient
