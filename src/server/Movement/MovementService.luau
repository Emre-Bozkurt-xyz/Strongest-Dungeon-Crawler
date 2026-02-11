--!strict
-- MovementService: server-side movement validation + authoritative helpers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Server = game:GetService("ServerScriptService").Server

local MovementSpec = require(ReplicatedStorage.Shared.Movement.MovementSpec)
local Clock = require(ReplicatedStorage.Shared.Time.Clock)
local Registrar = require(Server.Services.Registrar)

local MovementService = {}

export type DashSpec = MovementSpec.DashSpec
export type RollSpec = MovementSpec.RollSpec

local function getRootPart(entityId: string): BasePart?
	local entity = Registrar.getEntityById(entityId)
	if not entity then
		return nil
	end
	if entity:IsA("Model") then
		return entity:FindFirstChild("HumanoidRootPart") :: BasePart?
	end
	if entity:IsA("BasePart") then
		return entity
	end
	return nil
end

function MovementService.buildDashSpec(params: {
	id: string?,
	sourceSkill: string?,
	entityId: string,
	startTime: number?,
	duration: number?,
	distance: number?,
	direction: Vector3?,
}): DashSpec?
	local rootPart = getRootPart(params.entityId)
	if not rootPart then
		return nil
	end
	local direction = params.direction or rootPart.CFrame.LookVector
	local startTime = params.startTime or Clock.localNow()
	return MovementSpec.buildDashSpec({
		id = params.id,
		sourceSkill = params.sourceSkill,
		startTime = startTime,
		duration = params.duration,
		distance = params.distance,
		direction = direction,
	})
end

function MovementService.buildRollSpec(params: {
	id: string?,
	sourceSkill: string?,
	entityId: string,
	startTime: number?,
	duration: number?,
	distance: number?,
	direction: Vector3?,
}): RollSpec?
	local rootPart = getRootPart(params.entityId)
	if not rootPart then
		return nil
	end
	local direction = params.direction or rootPart.CFrame.LookVector
	local startTime = params.startTime or Clock.localNow()
	return MovementSpec.buildRollSpec({
		id = params.id,
		sourceSkill = params.sourceSkill,
		startTime = startTime,
		duration = params.duration,
		distance = params.distance,
		direction = direction,
	})
end

function MovementService.applyDash(entityId: string, spec: DashSpec): (() -> ())?
	local rootPart = getRootPart(entityId)
	if not rootPart then
		return nil
	end

	local attachment = Instance.new("Attachment", rootPart)
	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.Attachment0 = attachment
	linearVelocity.MaxForce = math.huge
	linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVelocity.Parent = rootPart

	local startTime = Clock.localNow()
	local conn: RBXScriptConnection? = nil
	local cleaned = false
	local function cleanup()
		if cleaned then
			return
		end
		cleaned = true
		if conn then
			conn:Disconnect()
		end
		if attachment then
			attachment:Destroy()
		end
		if linearVelocity then
			linearVelocity:Destroy()
		end
		if rootPart then
			rootPart.AssemblyLinearVelocity = Vector3.zero
			rootPart.AssemblyAngularVelocity = Vector3.zero
		end
	end

	conn = RunService.Heartbeat:Connect(function()
		local elapsed = Clock.localNow() - startTime
		if elapsed >= spec.duration then
			cleanup()
			return
		end
		linearVelocity.VectorVelocity = MovementSpec.computeVelocity(spec, elapsed)
	end)

	return cleanup
end

function MovementService.applyRoll(entityId: string, spec: RollSpec): (() -> ())?
	local rootPart = getRootPart(entityId)
	if not rootPart then
		return nil
	end

	local attachment = Instance.new("Attachment", rootPart)
	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.Attachment0 = attachment
	linearVelocity.MaxForce = math.huge
	linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVelocity.Parent = rootPart

	local startTime = Clock.localNow()
	local conn: RBXScriptConnection? = nil
	local cleaned = false
	local function cleanup()
		if cleaned then
			return
		end
		cleaned = true
		if conn then
			conn:Disconnect()
		end
		if attachment then
			attachment:Destroy()
		end
		if linearVelocity then
			linearVelocity:Destroy()
		end
		if rootPart then
			rootPart.AssemblyLinearVelocity = Vector3.zero
			rootPart.AssemblyAngularVelocity = Vector3.zero
		end
	end

	conn = RunService.Heartbeat:Connect(function()
		local elapsed = Clock.localNow() - startTime
		if elapsed >= spec.duration then
			cleanup()
			return
		end
		linearVelocity.VectorVelocity = MovementSpec.computeVelocity(spec, elapsed)
	end)

	return cleanup
end

return MovementService
