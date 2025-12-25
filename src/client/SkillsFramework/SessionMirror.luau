--!strict
-- SessionMirror.luau
-- Client-side mirror of server session state
-- Receives authoritative session updates and provides local query API

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SessionTypes = require(ReplicatedStorage.Shared.skills.SessionTypes)
local Networking = require(ReplicatedStorage.Shared.Networking)

type SkillSession = SessionTypes.SkillSession
type SessionState = SessionTypes.SessionState
type SessionEventPayload = SessionTypes.SessionEventPayload

-- ============================================================================
-- DEBUG CONFIGURATION
-- ============================================================================
local DEBUG = false -- Toggle for session updates
local DEBUG_DISCREPANCY = false -- Toggle for shadow mode discrepancy detection

local perfStats = {
	intervalStart = os.clock(),
	lastEventAt = nil :: number?,
	lastPredictionAt = nil :: number?,
	lastPredictionCancelAt = nil :: number?,
	lastPredictionReplaceAt = nil :: number?,
	lastSessionCount = 0,
	lastActiveCount = 0,
	peakSessionCount = 0,
	peakActiveCount = 0,
	eventsReceived = 0,
	predictionsStarted = 0,
	predictionsCancelled = 0,
	predictionsReplaced = 0,
	discrepancies = 0,
}

-- ============================================================================
-- MODULE STATE
-- ============================================================================
local SessionMirror = {
	sessions = {} :: { [string]: SkillSession }, -- All sessions by ID
	sessionsByCaster = {} :: { [string]: SkillSession }, -- Active session per caster
	predictedByCaster = {} :: { [string]: SkillSession }, -- Client-only predicted session per caster
	localPlayerId = nil :: string?,

	-- Stats for debugging/perf analysis
	totalEventsReceived = 0,
	totalDiscrepancies = 0,
	totalPredictionsStarted = 0,
	totalPredictionsCancelled = 0,
	totalPredictionsReplaced = 0,
}

local listeners: { (payload: SessionEventPayload, session: SkillSession) -> () } = {}

-- ============================================================================
-- PRIVATE HELPERS
-- ============================================================================

local function debugLog(operation: string, sessionId: string?, data: { [string]: any }?)
	if not DEBUG then
		return
	end

	local parts = { "[SESSION_CLIENT]", operation }
	if sessionId then
		table.insert(parts, "ID:" .. sessionId:sub(1, 8) .. "...")
	end
	if data then
		for k, v in data do
			table.insert(parts, `{k}={tostring(v)}`)
		end
	end
	print(table.concat(parts, " | "))
end

local function updateActiveSessionStats()
	local total = 0
	local active = 0
	for _, session in pairs(SessionMirror.sessions) do
		total += 1
		if session.state ~= "COMPLETED" and session.state ~= "CANCELLED" then
			active += 1
		end
	end
	perfStats.lastSessionCount = total
	perfStats.lastActiveCount = active
	if total > perfStats.peakSessionCount then
		perfStats.peakSessionCount = total
	end
	if active > perfStats.peakActiveCount then
		perfStats.peakActiveCount = active
	end
end

local function removeSession(sessionId: string)
	local session = SessionMirror.sessions[sessionId]
	if not session then
		return
	end
	SessionMirror.sessions[sessionId] = nil
	if SessionMirror.sessionsByCaster[session.casterId] == session then
		SessionMirror.sessionsByCaster[session.casterId] = nil
	end
	updateActiveSessionStats()
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

-- Get local player's active session
function SessionMirror.getMySession(): SkillSession?
	if not SessionMirror.localPlayerId then
		return nil
	end
	return SessionMirror.sessionsByCaster[SessionMirror.localPlayerId]
end

function SessionMirror.getLocalCasterId(): string?
	return SessionMirror.localPlayerId
end

-- Get any entity's active session
function SessionMirror.getSession(casterId: string): SkillSession?
	return SessionMirror.sessionsByCaster[casterId]
end

-- Check if local player is in a session
function SessionMirror.isInSession(): boolean
	return SessionMirror.getMySession() ~= nil
end

-- Check if local player can start a new skill
function SessionMirror.canStartSkill(): boolean
	local mySession = SessionMirror.getMySession()
	if not mySession then
		return true
	end

	-- Can't start if there's an active session (not terminal)
	return mySession.state == "COMPLETED" or mySession.state == "CANCELLED"
end

function SessionMirror.predictStart(
	skillId: string,
	combo: {
		currentStep: number,
		totalSteps: number,
		windowOpensAt: number?,
		windowExpiresAt: number?,
	}?,
	executionExpiresAt: number?
): SkillSession?
	local casterId = SessionMirror.localPlayerId
	if not casterId then
		return nil
	end

	local existing = SessionMirror.sessionsByCaster[casterId]
	if existing and not existing.isPredicted then
		return existing
	end

	local now = os.clock()
	SessionMirror.totalPredictionsStarted += 1
	perfStats.predictionsStarted += 1
	perfStats.lastPredictionAt = now
	local session: SkillSession
	if existing and existing.isPredicted then
		session = existing
	else
		session = {
			id = "__pred_" .. HttpService:GenerateGUID(false),
			skillId = skillId,
			casterId = casterId,
			state = "ACTIVE",
			stateEnteredAt = now,
			createdAt = now,
			lastActivity = now,
			executionExpiresAt = executionExpiresAt or (now + 10),
			recoveryEndsAt = nil,
			combo = nil,
			isPredicted = true,
		}
		SessionMirror.sessions[session.id] = session
	end

	session.skillId = skillId
	session.casterId = casterId
	session.state = "ACTIVE"
	session.stateEnteredAt = now
	session.lastActivity = now
	session.executionExpiresAt = executionExpiresAt or session.executionExpiresAt
	session.recoveryEndsAt = nil
	session.isPredicted = true
	session.combo = combo
			and {
				currentStep = combo.currentStep,
				totalSteps = combo.totalSteps,
				windowOpensAt = combo.windowOpensAt,
				windowExpiresAt = combo.windowExpiresAt,
				stepToken = 1,
			}
		or nil

	SessionMirror.sessionsByCaster[casterId] = session
	SessionMirror.predictedByCaster[casterId] = session
	updateActiveSessionStats()

	debugLog("PREDICTED", session.id, { caster = casterId, skill = skillId })

	return session
end

function SessionMirror.cancelPrediction(skillId: string?)
	local casterId = SessionMirror.localPlayerId
	if not casterId then
		return
	end
	local predicted = SessionMirror.predictedByCaster[casterId]
	if not predicted then
		return
	end
	if skillId and predicted.skillId ~= skillId then
		return
	end
	removeSession(predicted.id)
	SessionMirror.predictedByCaster[casterId] = nil
	SessionMirror.totalPredictionsCancelled += 1
	perfStats.predictionsCancelled += 1
	perfStats.lastPredictionCancelAt = os.clock()
	debugLog("PREDICTED_CANCEL", predicted.id, { caster = casterId, skill = predicted.skillId })
end

-- ============================================================================
-- EVENT HANDLING
-- ============================================================================

function SessionMirror._onServerEvent(payload: SessionEventPayload)
	SessionMirror.totalEventsReceived += 1
	perfStats.eventsReceived += 1
	perfStats.lastEventAt = os.clock()

	local sessionId = payload.sessionId
	local casterId = payload.casterId

	debugLog("EVENT_RECEIVED", sessionId, {
		caster = casterId,
		skill = payload.skillId,
		state = payload.state,
		reason = payload.reason or "none",
	})

	local predicted = SessionMirror.predictedByCaster[casterId]
	if predicted and predicted.skillId == payload.skillId then
		removeSession(predicted.id)
		SessionMirror.predictedByCaster[casterId] = nil
		SessionMirror.totalPredictionsReplaced += 1
		perfStats.predictionsReplaced += 1
		perfStats.lastPredictionReplaceAt = os.clock()
	end

	-- Update or create session
	local existingSession = SessionMirror.sessions[sessionId]

	if not existingSession then
		-- New session - create from server payload
		SessionMirror._createFromPayload(payload)
	else
		-- Update existing session
		SessionMirror._updateFromPayload(existingSession, payload)
	end

	-- Notify listeners (payload-first to avoid mutation surprises)
	local session = SessionMirror.sessions[payload.sessionId]
	if session then
		for _, cb in ipairs(listeners) do
			task.spawn(function()
				cb(payload, session)
			end)
		end
	end
end

function SessionMirror._createFromPayload(payload: SessionEventPayload)
	local session: SkillSession = {
		id = payload.sessionId,
		skillId = payload.skillId,
		casterId = payload.casterId,
		state = payload.state,
		stateEnteredAt = payload.stateEnteredAt,
		createdAt = payload.serverTime, -- Use server time as creation time
		lastActivity = payload.serverTime,
		executionExpiresAt = payload.executionExpiresAt,
		recoveryEndsAt = payload.recoveryEndsAt,
		isPredicted = nil,
		combo = if payload.combo
			then {
				currentStep = payload.combo.currentStep,
				totalSteps = payload.combo.totalSteps,
				windowOpensAt = payload.combo.windowOpensAt,
				windowExpiresAt = payload.combo.windowExpiresAt,
				stepToken = 1, -- We don't track token client-side
			}
			else nil,
	}

	SessionMirror.sessions[session.id] = session
	SessionMirror.sessionsByCaster[session.casterId] = session
	updateActiveSessionStats()

	debugLog("CREATED", session.id, { caster = session.casterId, skill = session.skillId })
end

function SessionMirror._updateFromPayload(session: SkillSession, payload: SessionEventPayload)
	-- Update all fields from server payload (full state reconciliation)
	session.state = payload.state
	session.stateEnteredAt = payload.stateEnteredAt
	session.lastActivity = payload.serverTime
	session.executionExpiresAt = payload.executionExpiresAt
	session.recoveryEndsAt = payload.recoveryEndsAt
	session.isPredicted = nil

	if payload.combo then
		if session.combo then
			session.combo.currentStep = payload.combo.currentStep
			session.combo.totalSteps = payload.combo.totalSteps
			session.combo.windowOpensAt = payload.combo.windowOpensAt
			session.combo.windowExpiresAt = payload.combo.windowExpiresAt
		else
			session.combo = {
				currentStep = payload.combo.currentStep,
				totalSteps = payload.combo.totalSteps,
				windowOpensAt = payload.combo.windowOpensAt,
				windowExpiresAt = payload.combo.windowExpiresAt,
				stepToken = 1,
			}
		end
	else
		session.combo = nil
	end

	debugLog("UPDATED", session.id, {
		caster = session.casterId,
		skill = session.skillId,
		state = payload.state,
	})
	updateActiveSessionStats()

	-- Clean up terminal sessions after a delay
	if payload.state == "COMPLETED" or payload.state == "CANCELLED" then
		task.delay(3, function()
			if SessionMirror.sessions[session.id] then
				removeSession(session.id)
				debugLog("CLEANUP", session.id, { caster = session.casterId })
			end
		end)
	end
end

function SessionMirror.onStateChanged(callback: (payload: SessionEventPayload, session: SkillSession) -> ()): () -> ()
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

-- ============================================================================
-- SHADOW MODE VALIDATION (Phase 1)
-- ============================================================================

-- Compare mirror state to old system state (for Phase 1 validation)
function SessionMirror.validateShadow(entityId: string, oldExecutionState: any?, oldComboState: any?)
	if not DEBUG_DISCREPANCY then
		return
	end

	local session = SessionMirror.sessionsByCaster[entityId]

	-- Check execution state
	if session and session.state ~= "COMPLETED" and session.state ~= "CANCELLED" then
		-- New system says there's an active session
		if not oldExecutionState or not oldExecutionState.isLocked then
			warn(`[SHADOW] MISMATCH | entity: {entityId} | new: {session.state} | old: no execution`)
			SessionMirror.totalDiscrepancies += 1
			perfStats.discrepancies += 1
		end
	elseif oldExecutionState and oldExecutionState.isLocked then
		-- Old system says locked but new system has no active session
		warn(`[SHADOW] MISMATCH | entity: {entityId} | new: no session | old: locked`)
		SessionMirror.totalDiscrepancies += 1
		perfStats.discrepancies += 1
	end

	-- Check combo state
	if session and session.combo and oldComboState then
		if session.combo.currentStep ~= oldComboState.currentStep then
			warn(
				`[SHADOW] MISMATCH | entity: {entityId} | new step: {session.combo.currentStep} | old step: {oldComboState.currentStep}`
			)
			SessionMirror.totalDiscrepancies += 1
			perfStats.discrepancies += 1
		end
	end
end

-- Print validation summary (for Phase 1 testing)
function SessionMirror.printValidationSummary()
	print(`[SHADOW] Validation Summary:`)
	print(`  Events Received: {SessionMirror.totalEventsReceived}`)
	print(`  Discrepancies: {SessionMirror.totalDiscrepancies}`)
	if SessionMirror.totalDiscrepancies == 0 then
		print(`  ✓ SHADOW MODE PASSING - Perfect sync!`)
	else
		warn(`  ✗ SHADOW MODE FAILING - {SessionMirror.totalDiscrepancies} discrepancies detected`)
	end
end

function SessionMirror.getPerfStats(): { [string]: any }
	updateActiveSessionStats()
	local snapshot = table.clone(perfStats)
	snapshot.intervalSeconds = os.clock() - perfStats.intervalStart
	snapshot.totalEventsReceived = SessionMirror.totalEventsReceived
	snapshot.totalPredictionsStarted = SessionMirror.totalPredictionsStarted
	snapshot.totalPredictionsCancelled = SessionMirror.totalPredictionsCancelled
	snapshot.totalPredictionsReplaced = SessionMirror.totalPredictionsReplaced
	snapshot.totalDiscrepancies = SessionMirror.totalDiscrepancies
	return snapshot
end

function SessionMirror.resetPerfStats()
	perfStats = {
		intervalStart = os.clock(),
		lastEventAt = nil,
		lastPredictionAt = nil,
		lastPredictionCancelAt = nil,
		lastPredictionReplaceAt = nil,
		lastSessionCount = 0,
		lastActiveCount = 0,
		peakSessionCount = 0,
		peakActiveCount = 0,
		eventsReceived = 0,
		predictionsStarted = 0,
		predictionsCancelled = 0,
		predictionsReplaced = 0,
		discrepancies = 0,
	}
	updateActiveSessionStats()
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

local function updateLocalPlayerId()
	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		return
	end
	local character = localPlayer.Character
	local entityId = character and character:GetAttribute("EntityId")
	if type(entityId) == "string" and entityId ~= "" then
		SessionMirror.localPlayerId = entityId
		return
	end
	-- Fallback to player name if attribute missing (should be rare)
	SessionMirror.localPlayerId = localPlayer.Name
end

function SessionMirror.initialize()
	updateLocalPlayerId()
	local localPlayer = Players.LocalPlayer
	if localPlayer then
		localPlayer.CharacterAdded:Connect(function(char)
			char:GetAttributeChangedSignal("EntityId"):Connect(function()
				updateLocalPlayerId()
			end)
			updateLocalPlayerId()
		end)
	end

	-- Listen to session events
	local dispatcher = Networking.client()
	dispatcher:on("SkillSession", function(payload: SessionEventPayload)
		SessionMirror._onServerEvent(payload)
	end)

	if DEBUG then
		print("[SESSION_CLIENT] SessionMirror initialized")
	end
end

return SessionMirror
