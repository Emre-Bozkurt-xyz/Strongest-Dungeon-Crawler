local BaseSkill = require(script.Parent.BaseSkill)
local ComboService = require(script.Parent.Parent.ComboService)
-- Cooldown start will be handled centrally on execution completion (SkillsManager listener)

local BaseComboSkill = {}
BaseComboSkill.__index = BaseComboSkill
setmetatable(BaseComboSkill, { __index = BaseSkill })

-- Contract: child implements onComboStep(self, step: number, requestData: any?)

function BaseComboSkill.new(casterId: string, data: any)
	local self = BaseSkill.new(casterId, data)
	setmetatable(self, BaseComboSkill)
	return self
end

function BaseComboSkill:use(requestData: any?): any
	local incomingCombo = requestData and requestData.combo or nil
	local req = requestData or {}
	if req.combo == nil and incomingCombo ~= nil then
		req.combo = incomingCombo
	end
	local combo = req.combo or incomingCombo
	local comboConfig = (self.config and self.config.combo) or nil
	local step = combo and combo.step or 1
	local total = combo and combo.total or (comboConfig and comboConfig.steps) or 1
	local token = combo and combo.token or 0

	local baseWindow = comboConfig and comboConfig.window or 0
	local baseHitDelays: { number }? = comboConfig and comboConfig.hitDelays or nil
	local baseStepDelays: { number }? = comboConfig and comboConfig.stepDelays or nil
	local baseRecovery = comboConfig and comboConfig.recovery or 0
	local baseStepDurations: { number }? = comboConfig and comboConfig.stepDurations or nil

	local baseHitDelay = if baseHitDelays and baseHitDelays[step] then baseHitDelays[step] else 0
	local timingResult = self:resolveTiming()
	req.timing = timingResult

	local durationScale = timingResult.durationScale
	local tempo = durationScale and durationScale ~= 0 and (1 / durationScale) or 1

	local hitDelay = baseHitDelay * durationScale
	local stepDelay = (baseStepDelays and baseStepDelays[step] or 0) * durationScale
	local window = (combo and combo.window or baseWindow) * durationScale
	local recovery = baseRecovery * durationScale
	local baseStepDuration = if baseStepDurations and baseStepDurations[step]
		then baseStepDurations[step]
		else baseHitDelay + (step == total and baseRecovery or 0)
	local stepDuration = math.max(baseStepDuration * durationScale, 0)

	local isFinal = (step == total)

	if step > 1 then
		self:emitComboWaitEnd()
	end

	if not self:applyResourceCost(req) then
		self:completeExecution("insufficient_resources")
		return
	end

	if step == 1 then
		self:beginExecution(nil, {
			allowChain = false,
			lockJump = true,
			timing = timingResult,
		})
	end

	self:_updateExecutionState({
		timing = timingResult,
		tempo = tempo,
		durationScale = durationScale,
		comboStep = step,
		comboTotal = total,
		hitDelay = hitDelay,
		recovery = recovery,
		window = window,
		stepDelay = stepDelay,
		stepDuration = stepDuration,
		baseStepDuration = baseStepDuration,
		targetDuration = stepDuration,
	})

	-- Let clients know the step started (to play the correct animation)
	self:emitStep(step, {
		total = total,
		tempo = tempo,
		speed = tempo,
		durationScale = durationScale,
		hitDelay = hitDelay,
		recovery = recovery,
		stepDuration = stepDuration,
		baseDuration = baseStepDuration,
		targetDuration = stepDuration,
	})

	-- Delay server-side hit logic to align with animation
	local delaySec = hitDelay
	if delaySec > 0 then
		task.delay(delaySec, function()
			self:onComboStep(step, req)
		end)
	else
		-- Immediate hit
		self:onComboStep(step, req)
	end

	local windowInfo = nil
	if token and token ~= 0 then
		windowInfo = ComboService.registerStepTiming(self.caster, self.name, token, {
			stepDuration = stepDuration,
			stepDelay = stepDelay,
			windowDuration = if not isFinal then window else 0,
			isFinal = isFinal,
			startedAt = combo and combo.startedAt or nil,
		})
	end

	if not isFinal and window > 0 and windowInfo then
		local openAt = windowInfo.windowOpenAt
		local closeAt = windowInfo.windowCloseAt
		if openAt and closeAt and closeAt > openAt then
			local nowClock = os.clock()
			local openDelay = math.max(0, openAt - nowClock)
			local waitDuration = math.max(0, closeAt - openAt)
			if waitDuration > 0 then
				task.delay(openDelay, function()
					if ComboService.isTokenCurrent(self.caster, self.name, token) then
						self:emitComboWaitStart(waitDuration, step, total)
					end
				end)
				task.delay(openDelay + waitDuration, function()
					if ComboService.isTokenCurrent(self.caster, self.name, token) then
						self:emitComboWaitEnd()
						self:completeExecution("expired")
					end
				end)
			end
		end
	elseif not isFinal and window > 0 then
		local waitDuration = window
		self:emitComboWaitStart(waitDuration, step, total)
		task.delay(waitDuration, function()
			if ComboService.isTokenCurrent(self.caster, self.name, token) then
				self:emitComboWaitEnd()
				self:completeExecution("expired")
			end
		end)
	end

	if isFinal then
		-- Schedule completion after the authoritative step duration (fallback to hit+recovery), ensuring onComboStep executes first.
		local completionDelay = if stepDuration > 0 then stepDuration else delaySec + recovery
		if completionDelay > 0 then
			task.delay(completionDelay, function()
				self:completeExecution()
			end)
		else
			-- Defer to guarantee order relative to immediate onComboStep
			task.defer(function()
				self:completeExecution()
			end)
		end
	end

	return { duration = stepDuration }
end

function BaseComboSkill:onComboStep(_step: number, _requestData: any?)
	error("BaseComboSkill:onComboStep must be implemented in child class")
end

return BaseComboSkill
