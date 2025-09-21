local BaseSkill = require(script.Parent.BaseSkill)
local ComboService = require(script.Parent.Parent.ComboService)
local CooldownService = require(script.Parent.Parent.CooldownService)

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
	local finalCd = combo and combo.finalCd or self.cooldown
    local hitDelays: {number}? = (self.config and self.config.combo and self.config.combo.hitDelays) :: {number}?

	local isFirst = (step == 1)
	local isFinal = (step == total)

	if not isFirst then
		self:emitComboWaitEnd()
	end
	if isFirst then
		self:emitStart({ step = step, total = total })
	end

	-- Let clients know the step started (to play the correct animation)
	self:emitStep(step, { total = total })

	-- Optionally delay server-side hit logic to align with animation
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
		local capturedStep = step
		self:emitComboWaitStart(window, step, total)
		task.delay(window, function()
			if ComboService.isExpired(self.player, self.name, token) then
				self:emitComboWaitEnd()
				self:emitEnd({ step = capturedStep, total = total, expired = true })
				-- cooldown on expiry
				if finalCd and finalCd > 0 then
					CooldownService.start(self.player, self.name, finalCd)
				end
			end
		end)
	end

	if isFinal then
		self:emitEnd({ step = step, total = total })
	end
end

function BaseComboSkill:onComboStep(_step: number, _requestData: any?)
	error("BaseComboSkill:onComboStep must be implemented in child class")
end

return BaseComboSkill
