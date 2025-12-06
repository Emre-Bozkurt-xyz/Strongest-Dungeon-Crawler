--!strict
-- Client-side combo state tracking - replicates server ComboService timing logic
-- Uses metadata (window, stepDurations, stepDelays) + timing results to calculate exact window boundaries
-- Enables client to gate skill requests with same logic as server

local SkillMetadataClient = require(script.Parent.SkillMetadataClient)
local ExecutionClient = require(script.Parent.ExecutionClient)

local ComboStateClient = {}

type ComboState = {
	skillName: string,
	currentStep: number,
	totalSteps: number,
	-- Window timing (calculated from metadata + timing scale)
	startTime: number, -- When this step started (os.clock)
	busyUntil: number, -- Step execution completes (startTime + stepDuration)
	windowOpenAt: number, -- When next input allowed (busyUntil + stepDelay)
	windowCloseAt: number?, -- When window expires (windowOpenAt + window)
	isFinal: boolean,
}

-- Active combo states per skill
local activeCombo: { [string]: ComboState } = {}

local function now(): number
	return os.clock()
end

-- Listen to execution completion to clear final combo states
-- Note: Server sends skillName=nil on unlock, so we track last locked skill ourselves
local lastLockedSkill: string? = nil

ExecutionClient.onChanged(function(locked: boolean, skillName: string?)
	if locked and skillName then
		-- Track which skill is locking
		lastLockedSkill = skillName
	elseif not locked and lastLockedSkill then
		-- Execution unlocked - check if it was a final combo step
		local state = activeCombo[lastLockedSkill]
		if state and state.isFinal then
			-- Final step completed, clear combo state
			activeCombo[lastLockedSkill] = nil
		end
		lastLockedSkill = nil
	end
end)

-- Calculate window timing using metadata (replicates ComboService.registerStepTiming)
local function calculateWindowTiming(
	skillName: string,
	step: number,
	totalSteps: number,
	durationScale: number,
	startTime: number
): ComboState?
	local metadata = SkillMetadataClient.get(skillName)
	if not metadata or not metadata.combo then
		warn(`🔮 [CLIENT-COMBO-STATE] {skillName} - No combo metadata found`)
		return nil
	end
	
	local combo = metadata.combo
	local isFinal = step >= totalSteps
	
	-- Get base values from metadata (same logic as server BaseComboSkill)
	local baseStepDuration
	if combo.stepDurations and combo.stepDurations[step] then
		baseStepDuration = combo.stepDurations[step]
	else
		local baseHitDelay = (combo.hitDelays and combo.hitDelays[step]) or 0
		local baseRecovery = (combo.recovery or 0)
		baseStepDuration = baseHitDelay + (isFinal and baseRecovery or 0)
	end
	
	local baseStepDelay = (combo.stepDelays and combo.stepDelays[step]) or 0
	local baseWindow = combo.window or 0
	
	-- Apply timing scale (from server)
	local stepDuration = baseStepDuration * durationScale
	local stepDelay = baseStepDelay * durationScale
	local window = baseWindow * durationScale
	
	-- Calculate timing gates (same as server ComboService)
	local busyUntil = startTime + stepDuration
	local windowOpenAt = busyUntil + stepDelay
	local windowCloseAt = if not isFinal then windowOpenAt + window else nil
	
	return {
		skillName = skillName,
		currentStep = step,
		totalSteps = totalSteps,
		startTime = startTime,
		busyUntil = busyUntil,
		windowOpenAt = windowOpenAt,
		windowCloseAt = windowCloseAt,
		isFinal = isFinal,
	}
end

-- Check if we can advance to next step (replicates ComboService.requestStep gating)
function ComboStateClient.canAdvance(skillName: string): (boolean, string?)
	local state = activeCombo[skillName]
	if not state then
		-- No active combo, can start fresh
		return true, nil
	end
	
	local t = now()
	
	-- Check if final step already played
	if state.isFinal then
		return false, "combo_complete"
	end
	
	-- Check if too early (still busy or before window opens)
	if t < state.windowOpenAt then
		return false, "combo_busy"
	end
	
	-- Check if window expired
	if state.windowCloseAt and t > state.windowCloseAt then
		activeCombo[skillName] = nil -- Clear expired state
		return false, "combo_expired"
	end
	
	-- Within window, can advance
	return true, nil
end

-- Predict next step number (doesn't check timing, just increments)
function ComboStateClient.predictNextStep(skillName: string, totalSteps: number): number
	local state = activeCombo[skillName]
	
	if state and not state.isFinal then
		local nextStep = state.currentStep + 1
		if nextStep <= totalSteps then
			return nextStep
		end
	end
	
	-- No active combo or complete, start fresh
	return 1
end

-- Reconcile with server confirmation (update state with authoritative timing)
function ComboStateClient.reconcile(
	skillName: string,
	serverStep: number,
	totalSteps: number,
	durationScale: number
)
	local startTime = now()
	local newState = calculateWindowTiming(skillName, serverStep, totalSteps, durationScale, startTime)
	
	if not newState then
		warn(`[ComboStateClient] Failed to calculate window timing for {skillName}`)
		return
	end
	
	activeCombo[skillName] = newState
end

-- Clear combo state (on completion or cancel)
function ComboStateClient.clear(skillName: string)
	activeCombo[skillName] = nil
end

-- Get current step (nil if no active combo or expired)
function ComboStateClient.getCurrentStep(skillName: string): number?
	local state = activeCombo[skillName]
	if not state then
		return nil
	end
	
	-- Check if window expired
	if state.windowCloseAt and now() > state.windowCloseAt then
		activeCombo[skillName] = nil
		return nil
	end
	
	return state.currentStep
end

-- Check if combo is active (has valid state)
function ComboStateClient.isActive(skillName: string): boolean
	return activeCombo[skillName] ~= nil
end

return ComboStateClient
