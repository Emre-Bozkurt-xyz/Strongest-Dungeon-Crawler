local BaseSkill = require(script.Parent.BaseSkill)
local ComboService = require(script.Parent.Parent.ComboService)
-- Cooldown start will be handled centrally on execution completion (SkillsManager listener)

local BaseComboSkill = {}
BaseComboSkill.__index = BaseComboSkill
setmetatable(BaseComboSkill, { __index = BaseSkill })

-- Contract: child implements onComboStep(self, step: number, requestData: any?)

function BaseComboSkill.new(player: Player, data: any)
	local self = BaseSkill.new(player, data)
	setmetatable(self, BaseComboSkill)
	return self
end

function BaseComboSkill:use(requestData: any?)
	local combo = requestData and requestData.combo or nil
	local step = combo and combo.step or 1
	local total = combo and combo.total or 1
	local window = combo and combo.window or 0
	local token = combo and combo.token or 0
    local hitDelays: {number}? = (self.config and self.config.combo and self.config.combo.hitDelays) :: {number}?

	local isFirst = (step == 1)
	-- Proper boolean final step check (previous 'or 0' introduced truthiness issues)
	local isFinal = (step == total)
	local recovery = (self.config and self.config.combo and self.config.combo.recovery) or 0

	if not isFirst then
		self:emitComboWaitEnd()
	end
	if isFirst then
		-- Begin execution with manual completion (no auto-duration) so variable player timing / stepDelays
		self:beginExecution(nil, true) -- allowChain = true for same-skill steps
	end

	-- Let clients know the step started (to play the correct animation)
	self:emitStep(step, { total = total })

	-- Delay server-side hit logic to align with animation
	local delaySec = if hitDelays and hitDelays[step] then hitDelays[step] else 0
	if delaySec > 0 then
		task.delay(delaySec, function()
			self:onComboStep(step, requestData)
		end)
	else
		-- Immediate hit
		self:onComboStep(step, requestData)
	end

	-- Open wait window (if more steps)
	if not isFinal and window > 0 then
		self:emitComboWaitStart(window, step, total)
		task.delay(window, function()
			if ComboService.isExpired(self.player, self.name, token) then
				self:emitComboWaitEnd()
				self:completeExecution("expired")
			end
		end)
	end

	if isFinal then
		-- Schedule completion strictly after the final hit delay + recovery, ensuring onComboStep executes first.
		local totalDelay = delaySec + (recovery or 0)
		if totalDelay > 0 then
			task.delay(totalDelay, function()
				self:completeExecution()
			end)
		else
			-- Defer to guarantee order relative to immediate onComboStep
			task.defer(function()
				self:completeExecution()
			end)
		end
	end
end

function BaseComboSkill:onComboStep(_step: number, _requestData: any?)
	error("BaseComboSkill:onComboStep must be implemented in child class")
end

return BaseComboSkill
