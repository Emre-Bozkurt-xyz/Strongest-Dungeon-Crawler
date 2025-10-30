-- ComboService: Centralized combo controller that enforces step timing, windows, and gating.

export type ComboAdvance = {
	step: number,
	token: number,
	total: number,
	isNewChain: boolean,
	startedAt: number,
}

export type StepTimingInfo = {
	stepDuration: number?, -- execution time locked to this step (already scaled)
	stepDelay: number?, -- additional delay before the next step may begin
	windowDuration: number?, -- duration of the follow-up window once open
	isFinal: boolean?,
	startedAt: number?,
}

export type StepTimingResult = {
	busyUntil: number?,
	windowOpenAt: number?,
	windowCloseAt: number?,
}

type ComboState = {
	step: number,
	steps: number,
	token: number,
	lastAdvanceTime: number,
	nextAllowedAt: number?,
	windowCloseAt: number?,
	busyUntil: number?,
	completed: boolean?,
	pendingToken: number?,
}

local ComboService = {}
type Caster = string
local states: { [Caster]: { [string]: ComboState } } = {}

local function now(): number
	return os.clock()
end

local function ensureCasterMap(caster: Caster): { [string]: ComboState }
	local m = states[caster]
	if not m then
		m = {}
		states[caster] = m
	end
	return m
end

local function resetState(caster: Caster, skillName: string)
	local m = states[caster]
	if not m then
		return
	end
	m[skillName] = nil
	if next(m) == nil then
		states[caster] = nil
	end
end

function ComboService.requestStep(caster: Caster, skillName: string, steps: number): ComboAdvance?
	if steps <= 0 then
		return nil
	end

	local m = ensureCasterMap(caster)
	local state = m[skillName]
	local t = now()

	if state then
		if state.pendingToken ~= nil then
			return nil
		end
		if state.completed then
			return nil
		end
		if state.nextAllowedAt and t < state.nextAllowedAt then
			return nil
		end
		if state.windowCloseAt and t > state.windowCloseAt then
			state.completed = true
			return nil
		else
			state.steps = steps
			if state.step >= state.steps then
				return nil
			end
		end
	end

	if not state then
		local newState: ComboState = {
			step = 1,
			steps = steps,
			token = 1,
			lastAdvanceTime = t,
			nextAllowedAt = nil,
			windowCloseAt = nil,
			busyUntil = nil,
			completed = false,
			pendingToken = 1,
		}
		m[skillName] = newState
		return {
			step = 1,
			token = 1,
			total = steps,
			isNewChain = true,
			startedAt = t,
		}
	end

	state.step += 1
	state.token += 1
	state.lastAdvanceTime = t
	state.pendingToken = state.token

	if state.step >= state.steps then
		state.completed = true
	else
		state.completed = false
	end

	return {
		step = state.step,
		token = state.token,
		total = state.steps,
		isNewChain = false,
		startedAt = t,
	}
end

function ComboService.registerStepTiming(
	caster: Caster,
	skillName: string,
	token: number,
	info: StepTimingInfo
): StepTimingResult?
	local m = states[caster]
	local state = m and m[skillName]
	if not state then
		return nil
	end
	if state.token ~= token then
		return nil
	end
	if state.pendingToken and state.pendingToken ~= token then
		return nil
	end

	local startTime = info.startedAt or now()
	local stepDuration = math.max(info.stepDuration or 0, 0)
	local stepDelay = math.max(info.stepDelay or 0, 0)
	local windowDuration = math.max(info.windowDuration or 0, 0)
	local isFinal = info.isFinal or false

	local busyUntil = startTime + stepDuration
	local windowOpenAt = busyUntil + stepDelay
	local windowCloseAt = if isFinal then nil else windowOpenAt + windowDuration

	state.busyUntil = busyUntil
	state.nextAllowedAt = if stepDelay > 0 or stepDuration > 0 then windowOpenAt else startTime
	state.windowCloseAt = windowCloseAt
	state.pendingToken = nil
	state.completed = isFinal

	return {
		busyUntil = busyUntil,
		windowOpenAt = windowOpenAt,
		windowCloseAt = windowCloseAt,
	}
end

function ComboService.isTokenCurrent(caster: Caster, skillName: string, token: number): boolean
	local m = states[caster]
	local state = m and m[skillName]
	if not state then
		return false
	end
	return state.token == token
end

function ComboService.clear(caster: Caster, skillName: string)
	resetState(caster, skillName)
end

function ComboService.getState(caster: Caster, skillName: string): ComboState?
	local m = states[caster]
	return m and m[skillName] or nil
end

return ComboService
