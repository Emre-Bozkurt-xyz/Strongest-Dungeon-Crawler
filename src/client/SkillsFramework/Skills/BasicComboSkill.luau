local BaseSkill = require(script.Parent.BaseSkill)

local BasicComboSkill = {}
BasicComboSkill.__index = BaseSkill
setmetatable(BasicComboSkill, BaseSkill)

function BasicComboSkill.new(name: string?, config: any?)
	local self = setmetatable(BaseSkill.new(name, config), BasicComboSkill)

	return self
end

function BasicComboSkill:use()
	local response = self:requestUse()

	if not response.success then
		return
	end

	local step = response.data.step
	local animKey = self.config.anim.comboSteps[step].key or self.config.anim.start

	local track = self:playAnimation(animKey, {
		duration = response.data.duration,
	})

	if track then
		track.Stopped:Connect(function()
			-- Combo finished
			if not response.data.isFinalStep then
				self:playAnimation(self.config.anim.comboSteps[step].key, {
					duration = response.data.duration,
				})
			end
		end)
	end
end

return BasicComboSkill
