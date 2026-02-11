--!strict
-- SkillPacer: client-side execution pacing + local cooldown/GCD scheduling.
-- Keeps UX consistent under latency by simulating timing locally.

local SkillMetadataClient = require(script.Parent.SkillMetadataClient)
local CooldownClient = require(script.Parent.CooldownClient)

type ComboState = {
	currentStep: number,
	totalSteps: number,
	windowOpensAt: number?,
	windowExpiresAt: number?,
	chainEndsAt: number,
}

type SkillState = {
	combo: ComboState?,
	cooldownPending: boolean,
	cooldownStartAt: number,
	cooldownDuration: number,
	gcdPending: boolean,
	gcdStartAt: number,
	gcdDuration: number,
}

local SkillPacer = {}

local states: { [string]: SkillState } = {}
local activeSession: { skillName: string, endsAt: number }? = nil
local pendingStepsBySkill: { [string]: { [number]: boolean } } = {}
local pendingAt: { [string]: number } = {}
local runnerActive = false
local UPDATE_INTERVAL = 0.1
local PENDING_TIMEOUT = 2.0 -- seconds; avoid stale pending locks under extreme lag

local function now(): number
	return os.clock()
end

local function resolveStepDuration(
	step: number,
	totalSteps: number,
	comboConfig: any,
	durationScale: number?
): (number, number, number)
	local scale = durationScale or 1
	local baseHitDelay = comboConfig and comboConfig.hitDelays and comboConfig.hitDelays[step] or 0
	local baseStepDelay = comboConfig and comboConfig.stepDelays and comboConfig.stepDelays[step] or 0
	local baseRecovery = comboConfig and comboConfig.recovery or 0
	local baseStepDuration = nil
	if comboConfig and comboConfig.stepDurations and comboConfig.stepDurations[step] then
		baseStepDuration = comboConfig.stepDurations[step]
	else
		baseStepDuration = baseHitDelay + (step == totalSteps and baseRecovery or 0)
	end

	local stepDuration = math.max(baseStepDuration * scale, 0)
	local stepDelay = baseStepDelay * scale
	local hitDelay = baseHitDelay * scale
	return stepDuration, stepDelay, hitDelay
end

local function getState(skillName: string): SkillState
	local state = states[skillName]
	if not state then
		state = {
			combo = nil,
			cooldownPending = false,
			cooldownStartAt = 0,
			cooldownDuration = 0,
			gcdPending = false,
			gcdStartAt = 0,
			gcdDuration = 0,
		}
		states[skillName] = state
	end
	return state
end

local function refreshState(state: SkillState, skillName: string)
	local t = now()

	if state.combo and t >= state.combo.chainEndsAt then
		state.combo = nil
		if activeSession and activeSession.skillName == skillName then
			activeSession = nil
		end
	end

	if activeSession and t >= activeSession.endsAt then
		if activeSession.skillName == skillName then
			activeSession = nil
		end
	end

	if state.cooldownPending and t >= state.cooldownStartAt then
		state.cooldownPending = false
		if state.cooldownDuration > 0 then
			CooldownClient.startLocal(skillName, state.cooldownDuration)
		end
	end

	if state.gcdPending and t >= state.gcdStartAt then
		state.gcdPending = false
		if state.gcdDuration > 0 then
			CooldownClient.startLocal("_GCD", state.gcdDuration)
		end
	end
end

local function ensureRunner()
	if runnerActive then
		return
	end
	runnerActive = true
	task.spawn(function()
		while runnerActive do
			for skillName, state in pairs(states) do
				refreshState(state, skillName)
			end
			if not activeSession then
				local anyPending = false
				for _, state in pairs(states) do
					if state.cooldownPending or state.gcdPending then
						anyPending = true
						break
					end
				end
				if not anyPending then
					runnerActive = false
					break
				end
			end
			task.wait(UPDATE_INTERVAL)
		end
	end)
end

local function isLockedByOtherSkill(skillName: string): boolean
	if not activeSession then
		return false
	end
	if activeSession.skillName == skillName then
		return false
	end
	if now() >= activeSession.endsAt then
		activeSession = nil
		return false
	end
	return true
end

function SkillPacer.isLocked(skillName: string): boolean
	local state = getState(skillName)
	refreshState(state, skillName)
	return isLockedByOtherSkill(skillName)
end

function SkillPacer.canStart(skillName: string): (boolean, string?)
	local state = getState(skillName)
	refreshState(state, skillName)

	if isLockedByOtherSkill(skillName) then
		return false, "locked"
	end

	if activeSession and activeSession.skillName == skillName then
		return false, "locked"
	end

	return true, nil
end

function SkillPacer.canAdvanceCombo(
	skillName: string,
	totalSteps: number
): (boolean, string?, number, boolean)
	local state = getState(skillName)
	refreshState(state, skillName)
	local pendingSteps = pendingStepsBySkill[skillName]
	if pendingSteps then
		local lastPending = pendingAt[skillName] or 0
		if now() - lastPending > PENDING_TIMEOUT then
			pendingStepsBySkill[skillName] = nil
			pendingSteps = nil
		end
	end

	if isLockedByOtherSkill(skillName) then
		return false, "locked", 1, false
	end

	if activeSession and activeSession.skillName == skillName and not state.combo then
		if now() < activeSession.endsAt then
			return false, "locked", 1, false
		end
	end

	local combo = state.combo
	if not combo then
		if pendingSteps then
			return false, "combo_pending", 1, false
		end
		return true, nil, 1, false
	end

	if combo.totalSteps ~= totalSteps then
		combo.totalSteps = totalSteps
	end

	if combo.currentStep >= combo.totalSteps then
		return false, "combo_complete", combo.totalSteps, true
	end

	local t = now()
	if not combo.windowOpensAt then
		return false, "combo_busy", combo.currentStep + 1, true
	end

	if t < combo.windowOpensAt then
		return false, "combo_busy", combo.currentStep + 1, true
	end

	if combo.windowExpiresAt and t > combo.windowExpiresAt then
		if pendingSteps then
			return false, "combo_pending", combo.currentStep, true
		end
		state.combo = nil
		if activeSession and activeSession.skillName == skillName then
			activeSession = nil
		end
		return true, nil, 1, false
	end

	local predictedStep = combo.currentStep + 1
	if pendingSteps and pendingSteps[predictedStep] then
		return false, "combo_pending", predictedStep, true
	end

	return true, nil, predictedStep, true
end

function SkillPacer.recordSkillUse(skillName: string, duration: number?, cooldown: number?, gcd: number?)
	local state = getState(skillName)
	refreshState(state, skillName)

	local t = now()
	local execDuration = math.max(duration or 0, 0)
	local endsAt = t + execDuration

	activeSession = { skillName = skillName, endsAt = endsAt }
	state.combo = nil

	state.cooldownDuration = math.max(cooldown or 0, 0)
	state.cooldownStartAt = endsAt
	state.cooldownPending = state.cooldownDuration > 0

	state.gcdDuration = math.max(gcd or 0, 0)
	state.gcdStartAt = endsAt
	state.gcdPending = state.gcdDuration > 0

	if execDuration <= 0 then
		refreshState(state, skillName)
	end
	ensureRunner()
end

function SkillPacer.recordComboStep(
	skillName: string,
	step: number,
	totalSteps: number,
	windowOpensAt: number?,
	windowExpiresAt: number?,
	stepDuration: number?,
	cooldown: number?,
	gcd: number?
)
	local state = getState(skillName)
	refreshState(state, skillName)

	local t = now()
	local duration = math.max(stepDuration or 0, 0)
	local isFinal = step >= totalSteps

	local chainEndsAt = t + duration
	if not isFinal then
		chainEndsAt = windowExpiresAt or chainEndsAt
	end

	state.combo = {
		currentStep = step,
		totalSteps = totalSteps,
		windowOpensAt = windowOpensAt,
		windowExpiresAt = windowExpiresAt,
		chainEndsAt = chainEndsAt,
	}

	activeSession = { skillName = skillName, endsAt = chainEndsAt }

	state.cooldownDuration = math.max(cooldown or 0, 0)
	state.cooldownStartAt = chainEndsAt
	state.cooldownPending = state.cooldownDuration > 0

	state.gcdDuration = math.max(gcd or 0, 0)
	state.gcdStartAt = chainEndsAt
	state.gcdPending = state.gcdDuration > 0

	if chainEndsAt <= t then
		refreshState(state, skillName)
	end
	ensureRunner()
end

function SkillPacer.beginHold(skillName: string)
	local state = getState(skillName)
	refreshState(state, skillName)
	activeSession = { skillName = skillName, endsAt = math.huge }
	state.combo = nil
	ensureRunner()
end

function SkillPacer.endHold(skillName: string)
	if activeSession and activeSession.skillName == skillName then
		activeSession = nil
	end
	local state = getState(skillName)
	refreshState(state, skillName)
end

function SkillPacer.confirmComboStep(
	skillName: string,
	confirmedStep: number?,
	totalSteps: number?,
	holdDuration: number?
)
	local state = getState(skillName)
	refreshState(state, skillName)
	if typeof(confirmedStep) ~= "number" then
		return
	end
	local total = totalSteps
	if total == nil and state.combo then
		total = state.combo.totalSteps
	end
	if total == nil then
		total = confirmedStep
	end
	local durationHold = math.max(holdDuration or 0, 0)
	if not state.combo then
		local t = now()
		state.combo = {
			currentStep = confirmedStep,
			totalSteps = total,
			windowOpensAt = nil,
			windowExpiresAt = nil,
			chainEndsAt = t + durationHold,
		}
		activeSession = { skillName = skillName, endsAt = state.combo.chainEndsAt }
		if durationHold <= 0 then
			refreshState(state, skillName)
		end
		ensureRunner()
		return
	end

	state.combo.currentStep = confirmedStep
	state.combo.totalSteps = total
	if confirmedStep >= total then
		state.combo.windowOpensAt = nil
		state.combo.windowExpiresAt = nil
		if durationHold > 0 then
			local newEnd = now() + durationHold
			if newEnd > state.combo.chainEndsAt then
				state.combo.chainEndsAt = newEnd
			end
			activeSession = { skillName = skillName, endsAt = state.combo.chainEndsAt }
		end
	end
end

export type ComboTiming = {
	stepDuration: number,
	stepDelay: number,
	hitDelay: number,
	window: number,
	windowOpensAt: number?,
	windowExpiresAt: number?,
}

function SkillPacer.computeComboTiming(
	step: number,
	totalSteps: number,
	comboConfig: any,
	durationScale: number?
): ComboTiming
	local stepDuration, stepDelay, hitDelay = resolveStepDuration(step, totalSteps, comboConfig or {}, durationScale)
	local baseWindow = comboConfig and comboConfig.window or 0
	local window = baseWindow * (durationScale or 1)

	local windowOpensAt = nil
	local windowExpiresAt = nil
	if step < totalSteps then
		local openDelay = stepDuration + stepDelay
		windowOpensAt = now() + openDelay
		windowExpiresAt = if window > 0 then windowOpensAt + window else windowOpensAt
	end

	return {
		stepDuration = stepDuration,
		stepDelay = stepDelay,
		hitDelay = hitDelay,
		window = window,
		windowOpensAt = windowOpensAt,
		windowExpiresAt = windowExpiresAt,
	}
end

function SkillPacer.getComboState(skillName: string): ComboState?
	local state = getState(skillName)
	refreshState(state, skillName)
	return state.combo
end

function SkillPacer.isActive(skillName: string): boolean
	local state = getState(skillName)
	refreshState(state, skillName)
	if state.combo then
		return true
	end
	if activeSession and activeSession.skillName == skillName then
		if now() < activeSession.endsAt then
			return true
		end
	end
	return false
end

function SkillPacer.getStateSnapshot(skillName: string): any
	local state = getState(skillName)
	refreshState(state, skillName)
	local combo = state.combo
	return {
		combo = combo and {
			currentStep = combo.currentStep,
			totalSteps = combo.totalSteps,
			windowOpensAt = combo.windowOpensAt,
			windowExpiresAt = combo.windowExpiresAt,
			chainEndsAt = combo.chainEndsAt,
		} or nil,
		activeSession = activeSession and {
			skillName = activeSession.skillName,
			endsAt = activeSession.endsAt,
		} or nil,
		cooldownPending = state.cooldownPending,
		cooldownStartAt = state.cooldownStartAt,
		cooldownDuration = state.cooldownDuration,
		gcdPending = state.gcdPending,
		gcdStartAt = state.gcdStartAt,
		gcdDuration = state.gcdDuration,
		now = now(),
	}
end

function SkillPacer.getMetadata(skillName: string)
	return SkillMetadataClient.get(skillName)
end

function SkillPacer.cancelSkill(skillName: string, cooldown: number?, gcd: number?)
	local state = getState(skillName)
	refreshState(state, skillName)

	state.combo = nil
	if activeSession and activeSession.skillName == skillName then
		activeSession = nil
	end

	local cd = math.max(cooldown or 0, 0)
	if cd > 0 then
		state.cooldownPending = false
		state.cooldownDuration = cd
		state.cooldownStartAt = now()
		CooldownClient.startLocal(skillName, cd)
	else
		state.cooldownPending = false
	end

	local gcdDur = math.max(gcd or 0, 0)
	if gcdDur > 0 then
		state.gcdPending = false
		state.gcdDuration = gcdDur
		state.gcdStartAt = now()
		CooldownClient.startLocal("_GCD", gcdDur)
	else
		state.gcdPending = false
	end
end

function SkillPacer.markServerPending(skillName: string, step: number?)
	if typeof(step) ~= "number" then
		return
	end
	local pendingSteps = pendingStepsBySkill[skillName]
	if not pendingSteps then
		pendingSteps = {}
		pendingStepsBySkill[skillName] = pendingSteps
	end
	pendingSteps[step] = true
	pendingAt[skillName] = now()
	ensureRunner()
end

function SkillPacer.clearServerPending(skillName: string, step: number?)
	local pendingSteps = pendingStepsBySkill[skillName]
	if not pendingSteps then
		return
	end
	if typeof(step) == "number" then
		pendingSteps[step] = nil
	else
		pendingStepsBySkill[skillName] = nil
	end
	pendingAt[skillName] = now()
end

return SkillPacer
