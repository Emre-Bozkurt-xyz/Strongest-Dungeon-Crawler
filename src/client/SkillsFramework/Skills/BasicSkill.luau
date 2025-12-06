local BaseSkill = require(script.Parent.BaseSkill)

local BasicSkill = {}
BasicSkill.__index = BasicSkill
setmetatable(BasicSkill, BaseSkill)

function BasicSkill.new(name: string?, config: any?)
	local self = setmetatable(BaseSkill.new(name, config), BasicSkill)
	return self
end

function BasicSkill:use()
	-- PRE-FLIGHT CHECK: Validate local state before starting animation
	local canUse, rejectionReason = self:canUseLocally()
	if not canUse then
		self:showRejectionFeedback(rejectionReason :: any)
		return
	end
	
	-- Get animation key
	local animSpec = self.config.anim and self.config.anim.start
	if not animSpec then
		warn("BasicSkill: No start animation configured for", self.name)
		return
	end
	
	-- Extract animKey string from spec
	local animKey = type(animSpec) == "table" and animSpec.key or animSpec
	if not animKey then
		warn("BasicSkill: Invalid animation spec for", self.name)
		return
	end
	
	-- PREDICT duration using BaseSkill helper
	local predictedDuration = self:predictDuration()
	
	-- PLAY ANIMATION IMMEDIATELY with predicted timing
	self:playAnimation(animKey, {
		duration = predictedDuration, -- may be nil, AnimationPlayer will use default
	})
	
	-- REQUEST server validation with callbacks
	self:requestUseAsync(
		function(_data)
			-- Server confirmed - prediction was successful
			-- No action needed; animation already playing with predicted timing
		end,
		function(_reason)
			-- Server rejected (rare - only on desync or edge cases)
			-- Animation already playing; will be interrupted by error feedback
		end
	)
end

return BasicSkill
