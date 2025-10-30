local BaseSkill = require(script.Parent.BaseSkill)

local BasicSkill = {}
BasicSkill.__index = BaseSkill
setmetatable(BasicSkill, BaseSkill)

function BasicSkill.new(name: string?, config: any?)
	local self = setmetatable(BaseSkill.new(name, config), BasicSkill)

	return self
end

function BasicSkill:use()
	local response = self:requestUse()

	if not response.success then
		return
	end

	self:playAnimation(self.config.anim.start, {
		duration = response.duration,
	})
end

return BasicSkill
