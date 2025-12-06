local BaseSkill = require(script.Parent.BaseSkill)
local ComboStateClient = require(script.Parent.Parent.ComboStateClient)

local BasicComboSkill = {}
BasicComboSkill.__index = BasicComboSkill
setmetatable(BasicComboSkill, { __index = BaseSkill })

function BasicComboSkill.new(name: string?, config: any?)
	local self = BaseSkill.new(name, config)
	setmetatable(self, BasicComboSkill)
	return self
end

function BasicComboSkill:use()
	-- Get combo config
	local comboSteps = self.config.anim and self.config.anim.comboSteps
	if not comboSteps or type(comboSteps) ~= "table" then
		warn("BasicComboSkill: No combo steps configured for", self.name)
		return
	end
	
	-- Extract combo parameters from server config (should match ClientSpec)
	local totalSteps = #comboSteps
	
	-- CHECK COMBO WINDOW TIMING (replicates server ComboService logic)
	local canAdvance, comboReason = ComboStateClient.canAdvance(self.name)
	if not canAdvance then
		self:showRejectionFeedback(comboReason :: any)
		return
	end
	
	-- PREDICT next combo step locally (instant, no server wait)
	local predictedStep = ComboStateClient.predictNextStep(self.name, totalSteps)
	
	-- PRE-FLIGHT CHECK: Validate local state before starting animation
	-- Pass predicted step for accurate resource cost check (combo steps may have different costs)
	-- Pass true for isComboAdvance to allow execution lock chaining if combo is active
	local hasActiveCombo = ComboStateClient.isActive(self.name)
	local canUse, rejectionReason = self:canUseLocally(predictedStep, hasActiveCombo)
	if not canUse then
		self:showRejectionFeedback(rejectionReason :: any)
		return
	end
	
	-- Get animation for predicted step
	local animSpec = comboSteps[predictedStep]
	local animKey = animSpec and animSpec.key or comboSteps[1].key
	
	-- Calculate predicted duration for this combo step
	local predictedDuration: number? = nil
	if self.config.combo and self.config.combo.stepDurations then
		local baseDuration = self.config.combo.stepDurations[predictedStep]
		if baseDuration then
			local _tempo, durationScale = self:predictTiming()
			if durationScale then
				predictedDuration = baseDuration * durationScale
			end
		end
	end
	
	-- PLAY ANIMATION IMMEDIATELY with predicted timing
	self:playAnimation(animKey, {
		duration = predictedDuration, -- may be nil, AnimationPlayer will use default
		step = predictedStep,
	})
	
	-- REQUEST server validation with callbacks
	self:requestUseAsync(
		function(data)
			-- Server confirmed - reconcile combo state
			local serverStep = data.step or 1
			local serverDuration = data.duration
			
			-- Calculate durationScale from server's authoritative duration
			local durationScale = 1.0
			if self.config.combo and self.config.combo.stepDurations then
				local baseDuration = self.config.combo.stepDurations[serverStep]
				if baseDuration and baseDuration > 0 and serverDuration then
					durationScale = serverDuration / baseDuration
				end
			end
			
			-- RECONCILE: Update combo state with server timing (calculates windows)
			ComboStateClient.reconcile(self.name, serverStep, totalSteps, durationScale)
			
			if serverStep ~= predictedStep then
				warn(`⚠️ [CLIENT-COMBO] {self.name} - Step mismatch: predicted={predictedStep} server={serverStep}`)
			end
		end,
		function(reason)
			-- Server rejected (rare - only on desync or edge cases)
			ComboStateClient.clear(self.name)
		end
	)
end

return BasicComboSkill
