--!strict
-- SessionManager.luau
-- Server-side unified session manager - replaces ExecutionService + ComboService
-- Single source of truth for skill execution state and combo progression

local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SessionTypes = require(ReplicatedStorage.Shared.skills.SessionTypes)
local Networking = require(ReplicatedStorage.Shared.Networking)

type SkillSession = SessionTypes.SkillSession
type SessionState = SessionTypes.SessionState
type SessionConfig = SessionTypes.SessionConfig
type SessionEventPayload = SessionTypes.SessionEventPayload

-- Get dispatcher singleton
local dispatcher = Networking.server()

-- ============================================================================
-- DEBUG CONFIGURATION
-- ============================================================================
local DEBUG = false -- Toggle for detailed logging
local DEBUG_HEARTBEAT = false -- Toggle for per-frame heartbeat logs (very verbose)
local TRANSITION_LOG_ENABLED = false
local TRANSITION_LOG_MAX = 200
local transitionLog: { [number]: { [string]: any } } = {}
local perfStats = {
	intervalStart = os.clock(),
	heartbeatTicks = 0,
	lastTickDuration = 0,
	avgTickDuration = 0,
	lastSessionCount = 0,
	lastActiveCount = 0,
	lastTerminalCount = 0,
	peakSessionCount = 0,
	peakActiveCount = 0,
	sessionsCreated = 0,
	sessionsCompleted = 0,
	sessionsCancelled = 0,
	totalTimeouts = 0,
	totalRecoveryCompletions = 0,
	totalComboWindowExpiries = 0,
}

-- ============================================================================
-- CONSTANTS
-- ============================================================================
local MAX_SESSION_DURATION = 30 -- Maximum lifetime of any session (seconds)
local CLEANUP_DELAY = 2 -- How long to keep terminal sessions before removal (seconds)

-- ============================================================================
-- MODULE STATE
-- ============================================================================
local SessionManager = {
	sessions = {} :: { [string]: SkillSession }, -- All sessions by ID
	sessionsByCaster = {} :: { [string]: SkillSession }, -- Active session per caster
	heartbeatConnection = nil :: RBXScriptConnection?,

	-- Stats for debugging
	totalSessionsCreated = 0,
	totalSessionsCompleted = 0,
	totalSessionsCancelled = 0,
}

-- Local event listeners (server-only)
local listeners: { [string]: { (SkillSession, SessionState, string?) -> () } } = {
	stateChanged = {},
}

-- Import legal transitions
local LEGAL_TRANSITIONS = SessionTypes.LEGAL_TRANSITIONS

-- ============================================================================
-- PRIVATE HELPERS
-- ============================================================================

local function debugLog(operation: string, sessionId: string?, data: { [string]: any }?)
	if not DEBUG then
		return
	end

	local parts = { "[SESSION]", operation }
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

local function recordTransition(entry: { [string]: any })
	if not TRANSITION_LOG_ENABLED then
		return
	end
	table.insert(transitionLog, entry)
	if #transitionLog > TRANSITION_LOG_MAX then
		table.remove(transitionLog, 1)
	end
end

local function formatSession(session: SkillSession): string
	local parts = {
		`{session.casterId}`,
		`{session.skillId}`,
		`{session.state}`,
	}
	if session.combo then
		table.insert(parts, `step {session.combo.currentStep}/{session.combo.totalSteps}`)
	end
	return table.concat(parts, " | ")
end

local function emitLocal(eventName: string, session: SkillSession, newState: SessionState, reason: string?)
	local eventListeners = listeners[eventName]
	if not eventListeners then
		return
	end
	for _, cb in ipairs(eventListeners) do
		task.spawn(function()
			local ok, err = pcall(cb, session, newState, reason)
			if not ok then
				warn(`[SESSION] LISTENER ERROR | event={eventName} | {tostring(err)}`)
			end
		end)
	end
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

function SessionManager.listen(eventName: string, callback: (SkillSession, SessionState, string?) -> ()): () -> ()
	local eventListeners = listeners[eventName]
	if not eventListeners then
		error(`SessionManager.listen: Unknown event '{eventName}'`)
	end
	table.insert(eventListeners, callback)
	return function()
		for i, cb in ipairs(eventListeners) do
			if cb == callback then
				table.remove(eventListeners, i)
				break
			end
		end
	end
end

function SessionManager.setTransitionLogEnabled(enabled: boolean, maxEntries: number?)
	TRANSITION_LOG_ENABLED = enabled == true
	if typeof(maxEntries) == "number" and maxEntries > 0 then
		TRANSITION_LOG_MAX = math.floor(maxEntries)
	end
end

function SessionManager.clearTransitionLog()
	table.clear(transitionLog)
end

function SessionManager.getTransitionLog(limit: number?): { [number]: { [string]: any } }
	local result = {}
	local max = typeof(limit) == "number" and math.max(0, math.floor(limit)) or #transitionLog
	local startIndex = math.max(1, #transitionLog - max + 1)
	for i = startIndex, #transitionLog do
		table.insert(result, transitionLog[i])
	end
	return result
end

function SessionManager.resetPerfStats()
	perfStats = {
		intervalStart = os.clock(),
		heartbeatTicks = 0,
		lastTickDuration = 0,
		avgTickDuration = 0,
		lastSessionCount = 0,
		lastActiveCount = 0,
		lastTerminalCount = 0,
		peakSessionCount = 0,
		peakActiveCount = 0,
		sessionsCreated = 0,
		sessionsCompleted = 0,
		sessionsCancelled = 0,
		totalTimeouts = 0,
		totalRecoveryCompletions = 0,
		totalComboWindowExpiries = 0,
	}
end

function SessionManager.getPerfStats(): { [string]: any }
	local snapshot = table.clone(perfStats)
	snapshot.intervalSeconds = os.clock() - perfStats.intervalStart
	snapshot.totalSessionsCreated = SessionManager.totalSessionsCreated
	snapshot.totalSessionsCompleted = SessionManager.totalSessionsCompleted
	snapshot.totalSessionsCancelled = SessionManager.totalSessionsCancelled
	return snapshot
end

function SessionManager.getSnapshot(includeTerminal: boolean?): { [string]: any }
	local now = os.clock()
	local snapshot = {
		now = now,
		total = 0,
		active = 0,
		terminal = 0,
		sessions = {} :: { [string]: any },
		byCaster = {} :: { [string]: any },
	}

	for sessionId, session in pairs(SessionManager.sessions) do
		local isTerminal = session.state == "COMPLETED" or session.state == "CANCELLED"
		snapshot.total += 1
		if isTerminal then
			snapshot.terminal += 1
		else
			snapshot.active += 1
		end

		if not isTerminal or includeTerminal == true then
			local combo = session.combo
			local entry = {
				id = session.id,
				casterId = session.casterId,
				skillId = session.skillId,
				state = session.state,
				createdAgo = now - session.createdAt,
				stateAge = now - session.stateEnteredAt,
				expiresIn = session.executionExpiresAt - now,
				recoveryIn = session.recoveryEndsAt and (session.recoveryEndsAt - now) or nil,
				combo = combo and {
					currentStep = combo.currentStep,
					totalSteps = combo.totalSteps,
					windowOpensIn = combo.windowOpensAt and (combo.windowOpensAt - now) or nil,
					windowExpiresIn = combo.windowExpiresAt and (combo.windowExpiresAt - now) or nil,
				} or nil,
			}
			snapshot.sessions[sessionId] = entry
			if SessionManager.sessionsByCaster[session.casterId] == session then
				snapshot.byCaster[session.casterId] = entry
			end
		end
	end

	return snapshot
end

function SessionManager.dumpSessions(includeTerminal: boolean?): { [string]: any }
	local snapshot = SessionManager.getSnapshot(includeTerminal)
	print(
		`[SESSION] Snapshot | total={snapshot.total} active={snapshot.active} terminal={snapshot.terminal} at={snapshot.now}`
	)
	for _, entry in pairs(snapshot.sessions) do
		local comboInfo = ""
		if entry.combo then
			comboInfo = ` combo={entry.combo.currentStep}/{entry.combo.totalSteps}`
		end
		local expiresText = "n/a"
		if typeof(entry.expiresIn) == "number" then
			expiresText = string.format("%.2f", entry.expiresIn)
		end
		print(`[SESSION] {entry.casterId} {entry.skillId} {entry.state}{comboInfo} expiresIn={expiresText}`)
	end
	return snapshot
end

-- Create a new session (called when skill use is approved)
function SessionManager.create(skillId: string, casterId: string, config: SessionConfig): SkillSession
	local now = os.clock()

	-- Generate unique ID
	local sessionId = HttpService:GenerateGUID(false)

	-- Build session
	local session: SkillSession = {
		id = sessionId,
		skillId = skillId,
		casterId = casterId,
		state = "CASTING",
		stateEnteredAt = now,
		createdAt = now,
		lastActivity = now,

		-- Hard timeout - session CANNOT exceed this
		executionExpiresAt = now + math.min(config.maxDuration or 10, MAX_SESSION_DURATION),

		combo = if config.combo
			then {
				currentStep = 1,
				totalSteps = config.combo.steps,
				windowOpensAt = nil,
				windowExpiresAt = nil,
				stepToken = 1,
			}
			else nil,
	}

	-- Store session
	SessionManager.sessions[sessionId] = session
	SessionManager.sessionsByCaster[casterId] = session
	SessionManager.totalSessionsCreated += 1

	-- Emit creation event
	SessionManager._emitStateChange(session, "CASTING", "created")
	perfStats.sessionsCreated += 1
	recordTransition({
		t = now,
		sessionId = sessionId,
		casterId = casterId,
		skillId = skillId,
		from = "IDLE",
		to = "CASTING",
		reason = "created",
	})

	debugLog("CREATE", sessionId, { skill = skillId, caster = casterId, maxDuration = config.maxDuration })

	return session
end

-- Get active session for a caster (nil if none)
function SessionManager.getActive(casterId: string): SkillSession?
	return SessionManager.sessionsByCaster[casterId]
end

-- Get session by ID
function SessionManager.get(sessionId: string): SkillSession?
	return SessionManager.sessions[sessionId]
end

-- Check if caster can start a new session
function SessionManager.canStart(casterId: string): boolean
	local existing = SessionManager.sessionsByCaster[casterId]
	if not existing then
		return true
	end

	-- Can't start if there's an active session (not terminal)
	return existing.state == "COMPLETED" or existing.state == "CANCELLED"
end

-- Transition session to new state
function SessionManager.transition(sessionId: string, newState: SessionState, reason: string?): boolean
	local session = SessionManager.sessions[sessionId]
	if not session then
		if DEBUG then
			warn(`[SESSION] TRANSITION FAILED | ID: {sessionId:sub(1, 8)}... | reason: session not found`)
		end
		return false
	end

	local oldState = session.state

	-- Check if transition is legal
	local allowed = LEGAL_TRANSITIONS[session.state]
	if not table.find(allowed, newState) then
		warn(`[SESSION] ILLEGAL TRANSITION | {formatSession(session)} | {oldState} → {newState} (not allowed)`)
		return false
	end

	-- Update state
	local now = os.clock()
	session.state = newState
	session.stateEnteredAt = now
	session.lastActivity = now
	recordTransition({
		t = now,
		sessionId = sessionId,
		casterId = session.casterId,
		skillId = session.skillId,
		from = oldState,
		to = newState,
		reason = reason,
	})

	-- Emit state change event to clients
	SessionManager._emitStateChange(session, newState, reason)

	-- Handle terminal states
	if newState == "COMPLETED" then
		SessionManager.totalSessionsCompleted += 1
		perfStats.sessionsCompleted += 1
		SessionManager._scheduleCleanup(sessionId)
	elseif newState == "CANCELLED" then
		SessionManager.totalSessionsCancelled += 1
		perfStats.sessionsCancelled += 1
		SessionManager._scheduleCleanup(sessionId)
	end

	debugLog("TRANSITION", sessionId, {
		caster = session.casterId,
		skill = session.skillId,
		transition = `{oldState} → {newState}`,
		reason = reason or "none",
	})

	return true
end

-- Advance combo step (for combo skills)
function SessionManager.advanceCombo(sessionId: string): boolean
	local session = SessionManager.sessions[sessionId]
	if not session or not session.combo then
		return false
	end
	if session.state ~= "ACTIVE" then
		return false
	end

	local now = os.clock()
	local opensAt = session.combo.windowOpensAt
	local expiresAt = session.combo.windowExpiresAt

	-- Ensure window has opened
	if opensAt and now < opensAt then
		debugLog("COMBO_ADVANCE_FAILED", sessionId, { reason = "window_not_open" })
		return false
	end

	-- Check if within window
	if expiresAt and now > expiresAt then
		debugLog("COMBO_ADVANCE_FAILED", sessionId, { reason = "window_expired" })
		return false -- Window expired
	end

	-- Check if more steps available
	if session.combo.currentStep >= session.combo.totalSteps then
		debugLog("COMBO_ADVANCE_FAILED", sessionId, { reason = "already_at_final_step" })
		return false -- Already at final step
	end

	-- Advance step
	local oldStep = session.combo.currentStep
	session.combo.currentStep += 1
	session.combo.stepToken += 1
	session.combo.windowOpensAt = nil
	session.combo.windowExpiresAt = nil -- Clear window until skill sets new one
	session.lastActivity = now

	-- Emit step event
	SessionManager._emitComboStep(session)

	debugLog("COMBO_ADVANCE", sessionId, {
		caster = session.casterId,
		skill = session.skillId,
		step = `{oldStep} → {session.combo.currentStep}`,
	})

	return true
end

-- Extend combo window (after successful step)
function SessionManager.extendComboWindow(sessionId: string, openDelay: number, windowDuration: number): ()
	local session = SessionManager.sessions[sessionId]
	if not session or not session.combo then
		return
	end

	local now = os.clock()
	local clampedOpenDelay = math.max(0, openDelay or 0)
	local clampedWindow = math.max(0, windowDuration or 0)
	local openAt = now + clampedOpenDelay
	local closeAt = if clampedWindow > 0 then openAt + clampedWindow else openAt

	session.combo.windowOpensAt = openAt
	session.combo.windowExpiresAt = closeAt
	session.lastActivity = now

	debugLog("COMBO_WINDOW_EXTEND", sessionId, {
		openDelay = clampedOpenDelay,
		windowDuration = clampedWindow,
		opensAt = openAt,
		expiresAt = closeAt,
	})

	-- Notify clients about updated window timing.
	SessionManager._emitStateChange(session, session.state, "combo_window_updated")
end

-- Force cancel (for interrupts, death, etc.)
function SessionManager.cancel(sessionId: string, reason: string): boolean
	return SessionManager.transition(sessionId, "CANCELLED", reason)
end

-- Start recovery period (after final hit, before completion)
function SessionManager.startRecovery(sessionId: string, duration: number): boolean
	local session = SessionManager.sessions[sessionId]
	if not session then
		return false
	end

	local now = os.clock()
	session.recoveryEndsAt = now + duration

	debugLog("RECOVERY_START", sessionId, { duration = duration, endsAt = session.recoveryEndsAt })

	return SessionManager.transition(sessionId, "RECOVERY", "recovery_started")
end

-- ============================================================================
-- PRIVATE METHODS
-- ============================================================================

-- Emit state change event to clients
function SessionManager._emitStateChange(session: SkillSession, newState: SessionState, reason: string?)
	local payload: SessionEventPayload = {
		sessionId = session.id,
		skillId = session.skillId,
		casterId = session.casterId,
		state = newState,
		reason = reason,

		-- Full timing info
		stateEnteredAt = session.stateEnteredAt,
		executionExpiresAt = session.executionExpiresAt,
		recoveryEndsAt = session.recoveryEndsAt,

		-- Full combo info if applicable
		combo = if session.combo
			then {
				currentStep = session.combo.currentStep,
				totalSteps = session.combo.totalSteps,
				windowOpensAt = session.combo.windowOpensAt,
				windowExpiresAt = session.combo.windowExpiresAt,
			}
			else nil,

		-- Server timestamp for latency compensation
		serverTime = os.clock(),
	}

	-- Note: Cast required until Dispatcher exports public API type
	(dispatcher :: any):emit("SkillSession", payload)

	emitLocal("stateChanged", session, newState, reason)
end

-- Emit combo step event (separate from state change for clarity)
function SessionManager._emitComboStep(session: SkillSession)
	-- For now, just emit a state change with reason "combo_step"
	-- This ensures clients get the updated combo state
	if session.combo then
		SessionManager._emitStateChange(session, session.state, `combo_step_{session.combo.currentStep}`)
	end
end

-- Schedule cleanup of terminal session
function SessionManager._scheduleCleanup(sessionId: string)
	task.delay(CLEANUP_DELAY, function()
		local session = SessionManager.sessions[sessionId]
		if not session then
			return
		end

		-- Remove from maps
		SessionManager.sessions[sessionId] = nil
		if SessionManager.sessionsByCaster[session.casterId] == session then
			SessionManager.sessionsByCaster[session.casterId] = nil
		end

		debugLog("CLEANUP", sessionId, { caster = session.casterId, skill = session.skillId })
	end)
end

-- ============================================================================
-- HEARTBEAT LOOP
-- ============================================================================

function SessionManager.startHeartbeat()
	if SessionManager.heartbeatConnection then
		return -- Already running
	end

	SessionManager.heartbeatConnection = RunService.Heartbeat:Connect(function()
		local tickStart = os.clock()
		local now = os.clock()
		local totalCount = 0
		local activeCount = 0
		local terminalCount = 0

		for sessionId, session in SessionManager.sessions do
			totalCount += 1
			-- Skip terminal states
			if session.state == "COMPLETED" or session.state == "CANCELLED" then
				terminalCount += 1
				continue
			end
			activeCount += 1

			if DEBUG_HEARTBEAT then
				print(`[SESSION] HEARTBEAT | {formatSession(session)}`)
			end

			-- Hard timeout - session exceeded maximum lifetime
			if now >= session.executionExpiresAt then
				if DEBUG then
					warn(`[SESSION] TIMEOUT | {formatSession(session)} | exceeded max duration`)
				end
				perfStats.totalTimeouts += 1
				SessionManager.transition(sessionId, "CANCELLED", "timeout")
				continue
			end

			-- Recovery period ended
			if session.state == "RECOVERY" and session.recoveryEndsAt and now >= session.recoveryEndsAt then
				perfStats.totalRecoveryCompletions += 1
				SessionManager.transition(sessionId, "COMPLETED", "recovery_ended")
				continue
			end

			-- Combo window expired (for combo skills in ACTIVE state awaiting input)
			if
				session.combo
				and session.combo.windowExpiresAt
				and now >= session.combo.windowExpiresAt
				and session.state == "ACTIVE"
			then
				-- Window closed - complete at current step
				if DEBUG then
					print(
						`[SESSION] COMBO_WINDOW_EXPIRED | {formatSession(session)} | completing at step {session.combo.currentStep}`
					)
				end
				perfStats.totalComboWindowExpiries += 1

				-- Phase 3: Transition to COMPLETED when combo window expires
				-- This replaces the task.delay() callbacks in BaseComboSkill
				SessionManager.transition(sessionId, "COMPLETED", "combo_window_expired")
				continue
			end
		end

		local tickDuration = os.clock() - tickStart
		perfStats.heartbeatTicks += 1
		perfStats.lastTickDuration = tickDuration
		perfStats.lastSessionCount = totalCount
		perfStats.lastActiveCount = activeCount
		perfStats.lastTerminalCount = terminalCount
		if totalCount > perfStats.peakSessionCount then
			perfStats.peakSessionCount = totalCount
		end
		if activeCount > perfStats.peakActiveCount then
			perfStats.peakActiveCount = activeCount
		end
		if perfStats.heartbeatTicks == 1 then
			perfStats.avgTickDuration = tickDuration
		else
			local n = perfStats.heartbeatTicks
			perfStats.avgTickDuration = perfStats.avgTickDuration + (tickDuration - perfStats.avgTickDuration) / n
		end
	end)

	print("[SESSION] Heartbeat started")
end

function SessionManager.stopHeartbeat()
	if SessionManager.heartbeatConnection then
		SessionManager.heartbeatConnection:Disconnect()
		SessionManager.heartbeatConnection = nil
		print("[SESSION] Heartbeat stopped")
	end
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

-- Auto-start heartbeat when required
SessionManager.startHeartbeat()

return SessionManager
