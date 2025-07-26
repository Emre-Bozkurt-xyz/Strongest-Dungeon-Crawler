local BaseSkill = {}
BaseSkill.__index = BaseSkill

function BaseSkill.new(player: Player, data: any)
	local self = setmetatable({}, BaseSkill)
	self.player = player
	self.name = data.name
	self.description = data.description
	self.level = data.level or 1
	self.cooldown = data.cooldown or 0
	return self
end

function BaseSkill:use()
	-- Implement skill usage logic here
	error("BaseSkill:use() must be implemented by child: " .. self.name)
end

return BaseSkill
