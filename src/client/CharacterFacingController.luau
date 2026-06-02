--!strict
-- Owns character yaw orientation policy so camera, movement, and UI basis consumers do not fight each other.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CharacterFacingController = {}
CharacterFacingController.__index = CharacterFacingController

export type CameraMode = "Free" | "OverShoulder"
export type FacingOptions = {
	restoreToCamera: boolean?,
	restoreLerpTime: number?,
}

type FacingOverride = {
	id: number,
	preForward: Vector3,
	prevAutoRotate: boolean,
	restoreToCamera: boolean,
	restoreLerpTime: number,
	attachment: Attachment?,
	align: AlignOrientation?,
}

type CharacterFacingControllerType = {
	player: Player,
	cameraMode: CameraMode,
	cameraYaw: number,
	_nextOverrideId: number,
	_override: FacingOverride?,
	_restoreTween: Tween?,
	setCameraMode: (self: CharacterFacingControllerType, mode: CameraMode) -> (),
	applyCameraYaw: (self: CharacterFacingControllerType, yaw: number) -> (),
	pushOverride: (self: CharacterFacingControllerType, direction: Vector3, opts: FacingOptions?) -> (() -> ()),
	clearOverride: (self: CharacterFacingControllerType, overrideId: number?) -> (),
	hasExternalOverride: (self: CharacterFacingControllerType) -> boolean,
	getPresentationBasisForward: (self: CharacterFacingControllerType, rootPart: BasePart?) -> Vector3?,
	destroy: (self: CharacterFacingControllerType) -> (),
}

local CharacterFacingController_Instance = nil

local function getCharacter(): Model?
	local player = Players.LocalPlayer
	return if player then player.Character else nil
end

local function getRootPart(): BasePart?
	local character = getCharacter()
	return if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

local function getHumanoid(): Humanoid?
	local character = getCharacter()
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
end

local function flattenDirection(direction: Vector3, fallback: Vector3?): Vector3
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude <= 1e-4 and fallback then
		flat = Vector3.new(fallback.X, 0, fallback.Z)
	end
	if flat.Magnitude <= 1e-4 then
		flat = Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

local function yawToForward(yaw: number): Vector3
	return flattenDirection(Vector3.new(-math.sin(yaw), 0, -math.cos(yaw)), nil)
end

local function getCameraForward(): Vector3
	local camera = Workspace.CurrentCamera
	local look = if camera then camera.CFrame.LookVector else Vector3.new(0, 0, -1)
	return flattenDirection(look, Vector3.new(0, 0, -1))
end

function CharacterFacingController.new(): CharacterFacingControllerType
	if CharacterFacingController_Instance then
		return CharacterFacingController_Instance
	end

	local self = setmetatable({}, CharacterFacingController) :: any
	CharacterFacingController_Instance = self
	self.player = Players.LocalPlayer
	self.cameraMode = "OverShoulder"
	self.cameraYaw = 0
	self._nextOverrideId = 0
	self._override = nil
	self._restoreTween = nil

	return self :: any
end

function CharacterFacingController:_cancelRestoreTween()
	local tween = self._restoreTween
	if tween then
		pcall(function()
			tween:Cancel()
		end)
		self._restoreTween = nil
	end
end

function CharacterFacingController:_setAutoRotate(enabled: boolean)
	local humanoid = getHumanoid()
	if humanoid then
		humanoid.AutoRotate = enabled
	end
end

function CharacterFacingController:_orientRootToForward(forward: Vector3)
	local rootPart = getRootPart()
	if not rootPart then
		return
	end
	local flat = flattenDirection(forward, rootPart.CFrame.LookVector)
	rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + flat)
end

function CharacterFacingController:setCameraMode(mode: CameraMode)
	self.cameraMode = mode
	if self._override then
		self:_setAutoRotate(false)
		return
	end
	self:_setAutoRotate(mode == "Free")
	if mode == "OverShoulder" then
		self:_orientRootToForward(yawToForward(self.cameraYaw))
	end
end

function CharacterFacingController:applyCameraYaw(yaw: number)
	self.cameraYaw = yaw
	if self.cameraMode ~= "OverShoulder" then
		return
	end
	if self._override then
		return
	end
	self:_cancelRestoreTween()
	self:_setAutoRotate(false)
	self:_orientRootToForward(yawToForward(yaw))
end

function CharacterFacingController:hasExternalOverride(): boolean
	return self._override ~= nil
end

function CharacterFacingController:getPresentationBasisForward(_rootPart: BasePart?): Vector3?
	local active = self._override
	if not active then
		return nil
	end
	return active.preForward
end

function CharacterFacingController:pushOverride(direction: Vector3, opts: FacingOptions?): (() -> ())
	self:clearOverride()

	local humanoid = getHumanoid()
	local rootPart = getRootPart()
	if not humanoid or not rootPart then
		return function() end
	end

	self:_cancelRestoreTween()

	local preForward = flattenDirection(rootPart.CFrame.LookVector, getCameraForward())
	local flat = flattenDirection(direction, preForward)
	local prevAutoRotate = humanoid.AutoRotate
	humanoid.AutoRotate = false

	local attachment = Instance.new("Attachment")
	attachment.Name = "FacingOverrideAttachment"
	attachment.Parent = rootPart

	local align = Instance.new("AlignOrientation")
	align.Attachment0 = attachment
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.RigidityEnabled = true
	align.MaxTorque = math.huge
	align.MaxAngularVelocity = math.huge
	align.Responsiveness = 200
	align.CFrame = CFrame.lookAt(Vector3.zero, flat)
	align.Parent = rootPart

	rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + flat)

	self._nextOverrideId += 1
	local overrideId = self._nextOverrideId
	self._override = {
		id = overrideId,
		preForward = preForward,
		prevAutoRotate = prevAutoRotate,
		restoreToCamera = if opts and opts.restoreToCamera == false then false else true,
		restoreLerpTime = if opts and opts.restoreLerpTime ~= nil then opts.restoreLerpTime else 0.12,
		attachment = attachment,
		align = align,
	}

	return function()
		self:clearOverride(overrideId)
	end
end

function CharacterFacingController:clearOverride(overrideId: number?)
	local active = self._override
	if not active then
		return
	end
	if overrideId ~= nil and active.id ~= overrideId then
		return
	end

	self._override = nil
	self:_cancelRestoreTween()

	if active.align then
		active.align:Destroy()
	end
	if active.attachment then
		active.attachment:Destroy()
	end

	local rootPart = getRootPart()
	local function finalize()
		if self.cameraMode == "OverShoulder" then
			self:_setAutoRotate(false)
			self:applyCameraYaw(self.cameraYaw)
		else
			self:_setAutoRotate(active.prevAutoRotate)
		end
	end

	local shouldRestore = active.restoreToCamera and self.cameraMode == "OverShoulder" and rootPart ~= nil
	if shouldRestore and rootPart then
		local targetForward = yawToForward(self.cameraYaw)
		local target = CFrame.lookAt(rootPart.Position, rootPart.Position + targetForward)
		local lerpTime = active.restoreLerpTime
		if lerpTime > 0 then
			local tween = TweenService:Create(
				rootPart,
				TweenInfo.new(lerpTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ CFrame = target }
			)
			self._restoreTween = tween
			tween.Completed:Once(function()
				if self._restoreTween == tween then
					self._restoreTween = nil
				end
				finalize()
			end)
			tween:Play()
			return
		end
		rootPart.CFrame = target
	end

	finalize()
end

function CharacterFacingController:destroy()
	self:clearOverride()
	self:_cancelRestoreTween()
	CharacterFacingController_Instance = nil :: any
end

function CharacterFacingController.getInstance(): CharacterFacingControllerType
	return CharacterFacingController_Instance or CharacterFacingController.new()
end

return CharacterFacingController
