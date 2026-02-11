local BaseSkill = require(script.Parent.BaseSkill)
local SkillPacer = require(script.Parent.Parent.SkillPacer)
local SkillMetadataClient = require(script.Parent.Parent.SkillMetadataClient)

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

	local metadata = SkillMetadataClient.get(self.name)
	local comboConfig = (metadata and metadata.combo) or self.config.combo or {}

	-- Extract combo parameters from server config (should match ClientSpec)
	local totalSteps = comboConfig.steps or #comboSteps
	if totalSteps > #comboSteps then
		totalSteps = #comboSteps
	end
	debugLog("Total steps:", totalSteps)

	-- CHECK COMBO WINDOW TIMING (replicates server ComboService logic)
	debugLog("Checking canAdvance...")
	local canAdvance, comboReason, predictedStep, hasActiveCombo = SkillPacer.canAdvanceCombo(self.name, totalSteps)
	debugLog("canAdvance:", canAdvance, "reason:", comboReason or "none")
	if not canAdvance then
		self:showRejectionFeedback(comboReason :: any)
		return
	end

	-- PREDICT next combo step locally (instant, no server wait)
	debugLog("Predicted step:", predictedStep)

	-- PRE-FLIGHT CHECK: Validate local state before starting animation
	-- Pass predicted step for accurate resource cost check (combo steps may have different costs)
	-- Pass true for isComboAdvance to allow execution lock chaining if combo is active
	debugLog("hasActiveCombo:", hasActiveCombo)
	local canUse, rejectionReason = self:canUseLocally(predictedStep, hasActiveCombo)
	debugLog("canUseLocally:", canUse, "reason:", rejectionReason or "none")
	if not canUse then
		self:showRejectionFeedback(rejectionReason :: any)
		return
	end

	local _tempo, durationScale = self:predictTiming()
	local timing = SkillPacer.computeComboTiming(predictedStep, totalSteps, comboConfig, durationScale)
	local predictedStepDuration = timing.stepDuration
	local windowOpensAt = timing.windowOpensAt
	local windowExpiresAt = timing.windowExpiresAt

	local cooldown = comboConfig.comboCooldown or (metadata and metadata.cooldown) or nil
	local gcd = metadata and metadata.gcd or nil
	SkillPacer.recordComboStep(
		self.name,
		predictedStep,
		totalSteps,
		windowOpensAt,
		windowExpiresAt,
		predictedStepDuration,
		cooldown,
		gcd
	)

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
	}, predictedDuration, { comboActive = hasActiveCombo })

	-- PLAY ANIMATION IMMEDIATELY with predicted timing (instant feedback, no server wait)
	self:playAnimation(animKey, {
		duration = predictedDuration, -- may be nil, AnimationPlayer will use default
		step = predictedStep,
	})

	-- REQUEST server validation with callbacks (non-blocking, happens in parallel)
	SkillPacer.markServerPending(self.name, predictedStep)
	self:requestUseAsync(function(data)
		SkillPacer.clearServerPending(self.name, predictedStep)
		-- Server confirmed - reconcile combo state
		local serverStep = data.step or 1
		if serverStep ~= predictedStep then
			warn(
				("[CLIENT-COMBO] %s - Step mismatch: predicted=%s server=%s"):format(
					self.name,
					tostring(predictedStep),
					tostring(serverStep)
				)
			)
		end
		SkillPacer.confirmComboStep(self.name, serverStep, totalSteps, predictedStepDuration)

	end, function(reason)
		-- Server rejected (rare - only on desync or edge cases)
		debugLog("Server rejected skill use, reason:", reason)

		SkillPacer.clearServerPending(self.name, predictedStep)
		-- CRITICAL: Cancel local prediction to stop animation/FX/sound immediately
		self:cancelLocalPrediction(reason)
		-- Note: cancelLocalPrediction already clears combo state and marks attempt rejected
	end)
end

return BasicComboSkill
