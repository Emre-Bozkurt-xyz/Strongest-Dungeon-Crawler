--!strict
-- MovementController: client-side predicted movement application + reconciliation hooks.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local MovementSpec = require(ReplicatedStorage.Shared.Movement.MovementSpec)
local Clock = require(ReplicatedStorage.Shared.Time.Clock)

local MovementController = {}

type ActiveMovement = {
	id: string,
	spec: MovementSpec.MovementSpec,
	startLocal: number,
	localEndAt: number,
	cleanup: (() -> ())?,
}

local active: ActiveMovement? = nil

type OrientationHandle = {
	cleanup: () -> (),
}

local orientationHandle: OrientationHandle? = nil

local function getRootPart(): BasePart?
	local player = Players.LocalPlayer
	if not player then
		return nil
	end
	local char = player.Character
	if not char then
		return nil
	end
	return char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function getHumanoid(): Humanoid?
	local player = Players.LocalPlayer
	if not player then
		return nil
	end
	local char = player.Character
	if not char then
		return nil
	end
	return char:FindFirstChildOfClass("Humanoid")
end

local function toYawCFrame(direction: Vector3): CFrame
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude <= 1e-4 then
		flat = Vector3.new(0, 0, -1)
	end
	return CFrame.lookAt(Vector3.zero, flat.Unit)
end

local function createMover(spec: MovementSpec.MovementSpec): (() -> ())?
	local rootPart = getRootPart()
	if not rootPart then
		return nil
	end

	local attachment = Instance.new("Attachment", rootPart)
	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.Attachment0 = attachment
	linearVelocity.MaxForce = math.huge
	linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVelocity.Parent = rootPart

	local startLocal = Clock.localNow()
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
		local elapsed = Clock.localNow() - startLocal
		if active and Clock.localNow() >= active.localEndAt then
			cleanup()
			active = nil
			return
		end
		linearVelocity.VectorVelocity = MovementSpec.computeVelocity(spec, elapsed)
	end)

	return cleanup
end

local function ensureId(spec: MovementSpec.MovementSpec): string
	if spec.id and spec.id ~= "" then
		return spec.id
	end
	return `dash-{math.floor(os.clock() * 1000)}`
end

local function startLocalMovement(spec: MovementSpec.MovementSpec): string
	local id = ensureId(spec)
	spec.id = id

	if active and active.cleanup then
		active.cleanup()
	end

	local duration = math.max(spec.duration, 0)
	local startLocal = Clock.localNow()
	active = {
		id = id,
		spec = spec,
		startLocal = startLocal,
		localEndAt = startLocal + duration,
		cleanup = createMover(spec),
	}
	return id
end

function MovementController.startLocalDash(spec: MovementSpec.DashSpec): string
	return startLocalMovement(spec)
end

function MovementController.startLocalRoll(spec: MovementSpec.RollSpec): string
	return startLocalMovement(spec)
end

function MovementController.cancelDash(id: string?, _reason: string?)
	if not active then
		return
	end
	if id and active.id ~= id then
		return
	end
	if active.cleanup then
		active.cleanup()
	end
	active = nil
end

function MovementController.reconcileDash(serverSpec: MovementSpec.MovementSpec, id: string?)
	if not active then
		return
	end
	if id and active.id ~= id then
		return
	end

	-- Update local spec to match server timing (avoid drift).
	if typeof(serverSpec.duration) == "number" then
		active.spec.duration = math.max(serverSpec.duration, 0)
	end
	if typeof(serverSpec.distance) == "number" then
		active.spec.distance = math.max(serverSpec.distance, 0)
	end
	if typeof(serverSpec.direction) == "Vector3" and serverSpec.direction.Magnitude > 1e-4 then
		active.spec.direction = serverSpec.direction.Unit
	end

	-- Only reconcile end-time (avoid mid-dash snapping).
	local serverNow = Clock.serverNow()
	local remaining = (serverSpec.startTime + serverSpec.duration) - serverNow
	if remaining <= 0 then
		MovementController.cancelDash(id, "server_completed")
		return
	end
	active.localEndAt = Clock.localNow() + remaining
end

export type FacingOptions = {
	restoreToCamera: boolean?,
	restoreLerpTime: number?,
}

function MovementController.startFacingDirection(direction: Vector3, opts: FacingOptions?): () -> ()
	if orientationHandle then
		orientationHandle.cleanup()
		orientationHandle = nil
	end

	local humanoid = getHumanoid()
	local rootPart = getRootPart()
	if not humanoid or not rootPart then
		return function() end
	end

	local preForward = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z)
	if preForward.Magnitude <= 1e-4 then
		local cam = workspace.CurrentCamera
		local camLook = cam and cam.CFrame.LookVector or Vector3.new(0, 0, -1)
		preForward = Vector3.new(camLook.X, 0, camLook.Z)
	end
	if preForward.Magnitude <= 1e-4 then
		preForward = Vector3.new(0, 0, -1)
	end
	preForward = preForward.Unit

	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude <= 1e-4 then
		flat = preForward
	end
	if flat.Magnitude <= 1e-4 then
		flat = Vector3.new(0, 0, -1)
	end
	flat = flat.Unit

	local prevAutoRotate = humanoid.AutoRotate
	humanoid.AutoRotate = false

	local attachment = Instance.new("Attachment")
	attachment.Name = "MovementFacingAttachment"
	attachment.Parent = rootPart

	rootPart:SetAttribute("ExternalFacing", true)
	rootPart:SetAttribute("ExternalFacingForward", preForward)

	local align = Instance.new("AlignOrientation")
	align.Attachment0 = attachment
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.RigidityEnabled = true
	align.MaxTorque = math.huge
	align.MaxAngularVelocity = math.huge
	align.Responsiveness = 200
	align.CFrame = CFrame.lookAt(Vector3.zero, flat)
	align.Parent = rootPart

	-- Apply immediate orientation so we don't wait on constraint settling.
	rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + flat)

	local cleaned = false
	local function cleanup()
		if cleaned then
			return
		end
		cleaned = true
		if align then
			align:Destroy()
		end
		if attachment then
			attachment:Destroy()
		end

		local function finalizeRestore()
		rootPart:SetAttribute("ExternalFacing", nil)
		rootPart:SetAttribute("ExternalFacingForward", nil)
			humanoid.AutoRotate = prevAutoRotate
		end

		local shouldRestore = opts == nil or opts.restoreToCamera ~= false
		if shouldRestore then
			local camera = workspace.CurrentCamera
			local look = camera and camera.CFrame.LookVector or rootPart.CFrame.LookVector
			local flatLook = Vector3.new(look.X, 0, look.Z)
			if flatLook.Magnitude > 1e-4 then
				local target = CFrame.lookAt(rootPart.Position, rootPart.Position + flatLook.Unit)
				local lerpTime = if opts and opts.restoreLerpTime ~= nil then opts.restoreLerpTime else 0.12
				if lerpTime > 0 then
					local tween = TweenService:Create(
						rootPart,
						TweenInfo.new(lerpTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{ CFrame = target }
					)
					tween:Play()
					tween.Completed:Once(finalizeRestore)
					return
				end
				rootPart.CFrame = target
			end
		end

		finalizeRestore()
	end

	orientationHandle = { cleanup = cleanup }
	return cleanup
end

function MovementController.cancelFacingDirection()
	if orientationHandle then
		orientationHandle.cleanup()
		orientationHandle = nil
	end
end

return MovementController
