local BaseSkill = require(script.Parent.BaseSkill)
local ComboStateClient = require(script.Parent.Parent.ComboStateClient)
local AttemptStore = require(script.Parent.Parent.AttemptStore)

-- DEBUG FLAG: Set to true to enable combo flow logging
local DEBUG_COMBO = false

local function debugLog(...)
	if DEBUG_COMBO then
		print("[COMBO-DEBUG]", ...)
	end
end

local BasicComboSkill = {}
BasicComboSkill.__index = BasicComboSkill
setmetatable(BasicComboSkill, { __index = BaseSkill })

function BasicComboSkill.new(name: string?, config: any?)
	local self = BaseSkill.new(name, config)
	setmetatable(self, BasicComboSkill)
	return self
end

function BasicComboSkill:use()
	debugLog("========== USE CALLED ==========")
	debugLog("Skill:", self.name)

	-- Get combo config
	local comboSteps = self.config.anim and self.config.anim.comboSteps
	if not comboSteps or type(comboSteps) ~= "table" then
		warn("BasicComboSkill: No combo steps configured for", self.name)
		return
	end

	-- Extract combo parameters from server config (should match ClientSpec)
	local totalSteps = #comboSteps
	debugLog("Total steps:", totalSteps)

	-- CHECK COMBO WINDOW TIMING (replicates server ComboService logic)
	debugLog("Checking canAdvance...")
	local canAdvance, comboReason = ComboStateClient.canAdvance(self.name)
	debugLog("canAdvance:", canAdvance, "reason:", comboReason or "none")
	if not canAdvance then
		self:showRejectionFeedback(comboReason :: any)
		return
	end

	-- PREDICT next combo step locally (instant, no server wait)
	local predictedStep = ComboStateClient.predictNextStep(self.name, totalSteps)
	debugLog("Predicted step:", predictedStep)

	-- PRE-FLIGHT CHECK: Validate local state before starting animation
	-- Pass predicted step for accurate resource cost check (combo steps may have different costs)
	-- Pass true for isComboAdvance to allow execution lock chaining if combo is active
	local hasActiveCombo = ComboStateClient.isActive(self.name)
	debugLog("hasActiveCombo:", hasActiveCombo)
	local canUse, rejectionReason = self:canUseLocally(predictedStep, hasActiveCombo)
	debugLog("canUseLocally:", canUse, "reason:", rejectionReason or "none")
	if not canUse then
		self:showRejectionFeedback(rejectionReason :: any)
		return
	end

	local _tempo, durationScale = self:predictTiming()
	local comboConfig = self.config.combo
	local baseStepDuration = nil
	local baseHitDelay = comboConfig and comboConfig.hitDelays and comboConfig.hitDelays[predictedStep] or 0
	local baseRecovery = comboConfig and comboConfig.recovery or 0
	if comboConfig and comboConfig.stepDurations and comboConfig.stepDurations[predictedStep] then
		baseStepDuration = comboConfig.stepDurations[predictedStep]
	else
		baseStepDuration = baseHitDelay + (predictedStep == totalSteps and baseRecovery or 0)
	end

	local predictedStepDuration = baseStepDuration * (durationScale or 1)
	local baseStepDelay = comboConfig and comboConfig.stepDelays and comboConfig.stepDelays[predictedStep] or 0
	local stepDelay = baseStepDelay * (durationScale or 1)
	local baseWindow = comboConfig and comboConfig.window or 0
	local window = baseWindow * (durationScale or 1)

	local windowOpensAt = nil
	local windowExpiresAt = nil
	if predictedStep < totalSteps then
		local openDelay = predictedStepDuration + stepDelay
		windowOpensAt = os.clock() + openDelay
		windowExpiresAt = if window > 0 then windowOpensAt + window else windowOpensAt
	end

	-- CREATE ATTEMPT: Begin tracking this skill use attempt
	local attemptRecord =
		AttemptStore.beginLocal(self.name, self.entityId, predictedStep, totalSteps, { comboActive = hasActiveCombo })
	self.currentAttemptId = attemptRecord.id

	-- IMMEDIATE CAST SOUND: Play before animation starts (no network wait)
	self:playCastSoundLocal()

	-- Get animation for predicted step
	local animSpec = comboSteps[predictedStep]
	local animKey = animSpec and animSpec.key or comboSteps[1].key

	-- Calculate predicted duration for this combo step
	local predictedDuration: number? = nil
	if predictedStepDuration > 0 then
		predictedDuration = predictedStepDuration
	end

	self:_predictSession({
		currentStep = predictedStep,
		totalSteps = totalSteps,
		windowOpensAt = windowOpensAt,
		windowExpiresAt = windowExpiresAt,
	}, predictedDuration)

	-- PLAY ANIMATION IMMEDIATELY with predicted timing (instant feedback, no server wait)
	self:playAnimation(animKey, {
		duration = predictedDuration, -- may be nil, AnimationPlayer will use default
		step = predictedStep,
	})

	-- REQUEST server validation with callbacks (non-blocking, happens in parallel)
	self:requestUseAsync(function(data)
		-- Server confirmed - reconcile combo state
		local serverStep = data.step or 1
		if serverStep ~= predictedStep then
			warn(`⚠️ [CLIENT-COMBO] {self.name} - Step mismatch: predicted={predictedStep} server={serverStep}`)
		end

	end, function(reason)
		-- Server rejected (rare - only on desync or edge cases)
		debugLog("Server rejected skill use, reason:", reason)

		-- CRITICAL: Cancel local prediction to stop animation/FX/sound immediately
		self:cancelLocalPrediction(reason)
		-- Note: cancelLocalPrediction already clears combo state and marks attempt rejected
	end)
end

return BasicComboSkill
