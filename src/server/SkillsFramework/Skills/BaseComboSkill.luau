local BaseSkill = require(script.Parent.BaseSkill)
local SessionManager = require(script.Parent.Parent.SessionManager) -- Phase 3: Unified system
-- Cooldown start will be handled centrally on execution completion (SkillsManager listener)

local BaseComboSkill = {}
BaseComboSkill.__index = BaseComboSkill
setmetatable(BaseComboSkill, { __index = BaseSkill })

local DEBUG_PHASE3 = false -- Phase 3: Track dual-system operation

local function debugPhase3(...: any)
	if DEBUG_PHASE3 then
		print("[PHASE3-COMBO]", ...)
	end
end

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
	if requestData and requestData.sessionId then
		self._sessionId = requestData.sessionId
	end
	local combo = req.combo or incomingCombo
	local comboConfig = (self.config and self.config.combo) or nil
	local step = combo and combo.step or 1
	local total = combo and combo.total or (comboConfig and comboConfig.steps) or 1
	local token = combo and combo.token or nil

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

	if not self:applyResourceCost(req) then
		if self._execToken then
			self:completeExecution("insufficient_resources")
		elseif self._sessionId then
			SessionManager.cancel(self._sessionId, "insufficient_resources")
		end
		return
	end

	if step == 1 then
		-- Pass nil duration - combo skills manually control completion timing
		self:beginExecution(nil, {
			allowChainSkill = self.name, -- Allow same skill to chain (combo advancement)
			lockJump = true,
			timing = timingResult,
			attemptId = requestData and requestData.attemptId or nil,
			sessionId = requestData and requestData.sessionId or nil, -- Phase 3: Pass session ID
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

	if self._sessionId and not isFinal then
		local windowOpenDelay = stepDuration + stepDelay
		SessionManager.extendComboWindow(self._sessionId, windowOpenDelay, window)
		debugPhase3(
			"Extended combo window:",
			self._sessionId:sub(1, 8),
			"openDelay=",
			windowOpenDelay,
			"window=",
			window
		)
	end

	if isFinal then
		-- Schedule completion after the authoritative step duration (fallback to hit+recovery), ensuring onComboStep executes first.
		local completionDelay = if stepDuration > 0 then stepDuration else delaySec + recovery
		debugPhase3(`Step {step} is FINAL, scheduling completion in {completionDelay}s`)
		if completionDelay > 0 then
			task.delay(completionDelay, function()
				debugPhase3(`Calling completeExecution for {self.name} after {completionDelay}s delay`)
				self:completeExecution()
			end)
		else
			-- Defer to guarantee order relative to immediate onComboStep
			task.defer(function()
				debugPhase3(`Calling completeExecution for {self.name} (deferred)`)
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
