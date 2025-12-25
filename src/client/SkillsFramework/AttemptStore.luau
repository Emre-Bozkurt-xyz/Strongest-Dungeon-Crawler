--!strict
-- AttemptStore: client-side SkillAttempt tracking using shared AttemptState
-- Keeps small records keyed by attemptId and enforces legal state transitions.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AttemptState = require(ReplicatedStorage.Shared.skills.AttemptState)
local Replicator = require(script.Parent.Parent.fx.Replicator)

type AttemptRecord = {
	id: string,
	skillId: string,
	casterId: number?,
	state: AttemptState.State,
	createdAt: number,
	lastUpdate: number,
	step: number?,
	totalSteps: number?,
	metadata: { [string]: any }?,
	reason: string?,
}

local AttemptStore = {}

local attempts: { [string]: AttemptRecord } = {}
local listeners: { (AttemptRecord, AttemptRecord?) -> () } = {}

local function now()
	return os.clock()
end

local function notify(newRec: AttemptRecord, oldRec: AttemptRecord?)
	for _, cb in ipairs(listeners) do
		local ok, err = pcall(cb, newRec, oldRec)
		if not ok then
			warn("AttemptStore listener error:", err)
		end
	end
end

local counter = 0
local function nextId(skillId: string): string
	counter += 1
	return `${skillId}-${math.floor(now() * 1000)}-${counter}`
end

local function transition(rec: AttemptRecord, nextState: AttemptState.State, reason: string?): AttemptRecord
	if not AttemptState.canTransition(rec.state, nextState) then
		return rec
	end
	local old = rec
	local updated: AttemptRecord = table.clone(rec)
	updated.state = nextState
	updated.lastUpdate = now()
	updated.reason = reason
	attempts[updated.id] = updated
	notify(updated, old)
	return updated
end

function AttemptStore.beginLocal(
	skillId: string,
	casterId: number?,
	step: number?,
	totalSteps: number?,
	metadata: { [string]: any }?
): AttemptRecord
	local id = nextId(skillId)
	local t = now()
	local rec: AttemptRecord = {
		id = id,
		skillId = skillId,
		casterId = casterId,
		state = AttemptState.States.LocalPredicted :: AttemptState.State,
		createdAt = t,
		lastUpdate = t,
		step = step,
		totalSteps = totalSteps,
		metadata = metadata,
		reason = nil,
	}
	attempts[id] = rec
	notify(rec, nil)
	return rec
end

function AttemptStore.markPending(id: string)
	local rec = attempts[id]
	if not rec then
		return
	end
	transition(rec, AttemptState.States.PendingServer :: AttemptState.State, nil)
end

function AttemptStore.confirm(id: string, data: any?)
	local rec = attempts[id]
	if not rec then
		return
	end
	local updated = transition(rec, AttemptState.States.ServerConfirmed :: AttemptState.State, nil)
	if data then
		if data.step then
			updated.step = data.step
		end
		if data.totalSteps then
			updated.totalSteps = data.totalSteps
		end
		if data.metadata then
			updated.metadata = data.metadata
		end
		updated.lastUpdate = now()
		attempts[id] = updated
	end
end

function AttemptStore.complete(id: string, reason: string?)
	local rec = attempts[id]
	if not rec then
		return
	end
	local updated = transition(rec, AttemptState.States.Completed :: AttemptState.State, reason)

	-- Cleanup FX for this attempt
	if updated.casterId and updated.casterId ~= 0 then
		local entityId = tostring(updated.casterId)
		Replicator.stopAllForAttempt(entityId, id)
	end
end

function AttemptStore.reject(id: string, reason: string?)
	local rec = attempts[id]
	if not rec then
		return
	end
	local updated = transition(rec, AttemptState.States.Rejected :: AttemptState.State, reason)

	-- Cleanup FX for this attempt
	if updated.casterId and updated.casterId ~= 0 then
		local entityId = tostring(updated.casterId)
		Replicator.stopAllForAttempt(entityId, id)
	end
end

function AttemptStore.get(id: string): AttemptRecord?
	return attempts[id]
end

function AttemptStore.onChanged(callback: (AttemptRecord, AttemptRecord?) -> ())
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

return AttemptStore
