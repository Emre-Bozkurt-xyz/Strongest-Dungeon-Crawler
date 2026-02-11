--!strict
-- HeldSkill: server-side base for press-and-hold skills with start/release flow.

local BaseSkill = require(script.Parent.BaseSkill)

local HeldSkill = {}
HeldSkill.__index = HeldSkill
setmetatable(HeldSkill, { __index = BaseSkill })

function HeldSkill.new(casterId, data)
	local self = BaseSkill.new(casterId, data)
	setmetatable(self, HeldSkill)
	self._holding = false
	self._holdToken = nil
	self._holdStartedAt = 0
	return self
end

function HeldSkill:isHolding(): boolean
	return self._holding == true
end

function HeldSkill:validateRelease(req: any?): (boolean, string?)
	if not self._holding then
		return false, "not_holding"
	end
	local holdToken = req and req.holdToken
	if not holdToken or holdToken ~= self._holdToken then
		return false, "hold_token_mismatch"
	end
	local maxHold = self.config and self.config.hold and self.config.hold.maxDuration
	if type(maxHold) == "number" and maxHold > 0 then
		local elapsed = os.clock() - (self._holdStartedAt or 0)
		if elapsed > maxHold then
			return false, "hold_expired"
		end
	end
	return true, nil
end

-- Override in subclasses for charge setup on server.
function HeldSkill:onStart(_req: any?): any
	return { success = true }
end

-- Override in subclasses to perform actual release logic.
function HeldSkill:onRelease(_req: any?): any
	return { success = true }
end

function HeldSkill:startHold(requestData: any?): (any?, string?)
	if self._holding then
		return nil, "already_holding"
	end
	local req = requestData or {}
	local holdToken = req.holdToken
	if type(holdToken) ~= "string" or holdToken == "" then
		return nil, "missing_hold_token"
	end
	self._holding = true
	self._holdToken = holdToken
	self._holdStartedAt = os.clock()
	self:beginExecution(nil, {
		sessionId = req.sessionId,
		timing = self:resolveTiming(),
		attemptId = req.attemptId,
	})
	local result = self:onStart(req)
	return result or { success = true }, nil
end

function HeldSkill:releaseHold(requestData: any?): (any?, string?)
	local ok, reason = self:validateRelease(requestData)
	if not ok then
		self._holding = false
		self._holdToken = nil
		return nil, reason
	end
	self._holding = false
	self._holdToken = nil
	local result = self:onRelease(requestData or {})
	if not result then
		return nil, "blocked"
	end
	return result, nil
end

return HeldSkill
