--!strict
-- Client-side combo state tracking using SessionMirror
-- Uses authoritative server window timings (windowOpensAt/windowExpiresAt) directly from sessions
-- No client-side recalculation needed - SessionManager is single source of truth

local SessionMirror = require(script.Parent.SessionMirror)

-- DEBUG FLAG: Set to true to enable combo state logging
local DEBUG_COMBO = false

local function debugLog(...)
	if DEBUG_COMBO then
		print("[COMBO-STATE]", ...)
	end
end

local ComboStateClient = {}

local function now(): number
	return os.clock()
end

-- Check if we can advance to next step (uses SessionMirror's authoritative window timing)
function ComboStateClient.canAdvance(skillName: string): (boolean, string?)
	debugLog("canAdvance called for", skillName)

	local localCaster = SessionMirror.getLocalCasterId()
	if not localCaster then
		debugLog("  No local caster ID")
		return true, nil
	end

	local session = SessionMirror.getSession(localCaster)
	if not session then
		-- No active session, can start fresh
		debugLog("  No active session -> can start fresh")
		return true, nil
	end

	-- Only gate for matching skill
	if session.skillId ~= skillName then
		debugLog("  Session is for different skill (", session.skillId, ") -> can start fresh")
		return true, nil
	end

	-- Check terminal states
	if session.state == "COMPLETED" or session.state == "CANCELLED" then
		debugLog("  Session is terminal (", session.state, ") -> can start fresh")
		return true, nil
	end

	-- Non-combo sessions always allow (single execution)
	if not session.combo then
		debugLog("  Non-combo session, allowing")
		return true, nil
	end

	local t = now()
	local combo = session.combo

	debugLog("  Combo session: step=", combo.currentStep, "totalSteps=", combo.totalSteps)
	debugLog(
		"  Window: opensAt=",
		combo.windowOpensAt and string.format("%.3f", combo.windowOpensAt) or "nil",
		"expiresAt=",
		combo.windowExpiresAt and string.format("%.3f", combo.windowExpiresAt) or "nil"
	)

	-- Check if final step already played
	local isFinal = combo.currentStep >= combo.totalSteps
	if isFinal then
		debugLog("  BLOCKED: combo_complete (isFinal=true)")
		return false, "combo_complete"
	end

	-- Check window timing (authoritative from server)
	if not combo.windowOpensAt then
		-- Window not yet set (execution just started), block
		debugLog("  BLOCKED: combo_busy (window not yet open)")
		return false, "combo_busy"
	end

	-- Check if too early (before window opens)
	if t < combo.windowOpensAt then
		local diff = combo.windowOpensAt - t
		debugLog("  BLOCKED: combo_busy (now < windowOpensAt, diff=", string.format("%.3f", diff), ")")
		return false, "combo_busy"
	end

	-- Check if window expired
	if combo.windowExpiresAt and t > combo.windowExpiresAt then
		local diff = t - combo.windowExpiresAt
		debugLog("  BLOCKED: combo_expired (now > windowExpiresAt, diff=", string.format("%.3f", diff), ")")
		return false, "combo_expired"
	end

	-- Within window, can advance
	debugLog("  OK: within window, can advance")
	return true, nil
end

-- Predict next step number (uses SessionMirror's authoritative step count)
function ComboStateClient.predictNextStep(skillName: string, totalSteps: number): number
	debugLog("predictNextStep called for", skillName, "totalSteps=", totalSteps)

	local localCaster = SessionMirror.getLocalCasterId()
	if not localCaster then
		debugLog("  No local caster, returning 1")
		return 1
	end

	local session = SessionMirror.getSession(localCaster)
	if not session or session.skillId ~= skillName then
		debugLog("  No matching session, returning 1")
		return 1
	end

	if session.state == "COMPLETED" or session.state == "CANCELLED" then
		debugLog("  Session is terminal, returning 1")
		return 1
	end

	if not session.combo then
		debugLog("  Non-combo skill, returning 1")
		return 1
	end

	local currentStep = session.combo.currentStep
	local isFinal = currentStep >= session.combo.totalSteps

	if not isFinal then
		local nextStep = currentStep + 1
		debugLog("  Current step=", currentStep, "-> next step=", nextStep)
		return nextStep
	end

	-- Final step already, start fresh
	debugLog("  Final step reached, returning 1")
	return 1
end

-- Reconcile with server confirmation (no longer needed - SessionMirror provides authoritative state)
-- Get current step (uses SessionMirror's authoritative step count)
function ComboStateClient.getCurrentStep(skillName: string): number?
	local localCaster = SessionMirror.getLocalCasterId()
	if not localCaster then
		return nil
	end

	local session = SessionMirror.getSession(localCaster)
	if not session or session.skillId ~= skillName then
		return nil
	end

	if session.state == "COMPLETED" or session.state == "CANCELLED" then
		return nil
	end

	if not session.combo then
		return nil
	end

	return session.combo.currentStep
end

-- Check if combo is active (has valid session)
function ComboStateClient.isActive(skillName: string): boolean
	local localCaster = SessionMirror.getLocalCasterId()
	if not localCaster then
		debugLog("isActive called for", skillName, "= false (no local caster)")
		return false
	end

	local session = SessionMirror.getSession(localCaster)
	local active = session ~= nil
		and session.skillId == skillName
		and session.combo ~= nil
		and session.state ~= "COMPLETED"
		and session.state ~= "CANCELLED"
	debugLog("isActive called for", skillName, "=", active)
	return active
end

return ComboStateClient
