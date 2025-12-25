local BaseSkill = require(script.Parent.BaseSkill)
local RunService = game:GetService("RunService")

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
		sessionId = requestData and requestData.sessionId or nil, -- Phase 3
	})
	self:_updateExecutionState({
		timing = timing,
		tempo = tempo,
		durationScale = durationScale,
	})

	local rootPart = self:getCasterRootPart()
	local humanoid = rootPart and rootPart.Parent:FindFirstChildOfClass("Humanoid")
	if rootPart and humanoid then
		local dashDistance = self.config.distance
		local dashTime = executionDuration
		local direction = (requestData and requestData.direction and requestData.direction.Unit)
			or rootPart.CFrame.LookVector

		local linearVelocity = Instance.new("LinearVelocity")
		local attachment = Instance.new("Attachment", rootPart)
		linearVelocity.Attachment0 = attachment
		linearVelocity.MaxForce = math.huge
		linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
		linearVelocity.Parent = rootPart

		local k = 6
		local minFactor = 0.15
		local startTime = tick()

		local effectiveK = 1 - minFactor
		local v0 = (dashDistance * k) / (dashTime * (1 - math.exp(-k * effectiveK)))

		local conn
		conn = RunService.Heartbeat:Connect(function()
			local elapsed = tick() - startTime
			if elapsed >= dashTime then
				conn:Disconnect()
				attachment:Destroy()
				linearVelocity:Destroy()
				return
			end

			local t = elapsed / dashTime
			local decay = math.exp(-k * t)
			local speedFactor = math.max(decay, minFactor)
			linearVelocity.VectorVelocity = direction * (v0 * speedFactor)
		end)
	end

	task.delay(executionDuration, function()
		self:completeExecution()
	end)

	-- Return success response for client
	return {
		success = true,
		data = {
			duration = executionDuration,
		},
	}
end

return Dash
