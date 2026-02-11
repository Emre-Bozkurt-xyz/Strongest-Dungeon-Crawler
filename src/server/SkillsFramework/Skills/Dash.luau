local BaseSkill = require(script.Parent.BaseSkill)
local MovementService = require(game:GetService("ServerScriptService").Server.Movement.MovementService)
local Registrar = require(game:GetService("ServerScriptService").Server.Services.Registrar)
local Clock = require(game:GetService("ReplicatedStorage").Shared.Time.Clock)

local Dash = {}
Dash.__index = Dash

setmetatable(Dash, { __index = BaseSkill })

function Dash.new(casterId: string, data: any)
	local self = BaseSkill.new(casterId, data)
	setmetatable(self, Dash)
	return self
end

function Dash:use(requestData: any?)
	local timing = self:resolveTiming()

	if not self:applyResourceCost({ timing = timing }) then
		return
	end

	local durationScale = timing.durationScale
	local tempo = durationScale and durationScale ~= 0 and (1 / durationScale) or 1
	local executionDuration = self.config.baseDuration * durationScale

	self:beginExecution(executionDuration, {
		lockJump = true,
		allowChain = false,
		autoComplete = false,
		timing = timing,
		sessionId = requestData and requestData.sessionId or nil,
	})
	self:_updateExecutionState({
		timing = timing,
		tempo = tempo,
		durationScale = durationScale,
	})

	if self._dashCleanup then
		self._dashCleanup()
		self._dashCleanup = nil
	end

	local spec = MovementService.buildDashSpec({
		id = requestData and requestData.attemptId or nil,
		sourceSkill = self.name,
		entityId = self.casterId,
		startTime = Clock.localNow(),
		duration = executionDuration,
		distance = self.config.distance,
		direction = requestData and requestData.direction or nil,
	})

	local applyOnServer = not Registrar.isPlayerEntity(self.casterId)
	if spec and applyOnServer then
		self._dashCleanup = MovementService.applyDash(self.casterId, spec)
	end

	task.delay(executionDuration, function()
		if self._dashCleanup then
			self._dashCleanup()
			self._dashCleanup = nil
		end
		self:completeExecution()
	end)

	-- Return success response for client
	return {
		success = true,
		data = {
			duration = executionDuration,
			movement = spec,
		},
	}
end

function Dash:onCancelled(_reason: string?)
	if self._dashCleanup then
		self._dashCleanup()
		self._dashCleanup = nil
	end
end

return Dash
