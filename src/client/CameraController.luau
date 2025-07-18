--!strict
-- Camera Controller - Handles over-the-shoulder camera positioning

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local WorldGUIManager = require(script.Parent.WorldGUIManager)

local CameraController = {}
CameraController.__index = CameraController

-- Configuration
local CAMERA_OFFSET = Vector3.new(3, 1.8, 1.5) -- Right, Up, Forward from player
local FOLLOW_SMOOTHNESS = 0.5 -- How smoothly camera follows player (0-1)
local LOOK_SMOOTHNESS = 0.15 -- How smoothly camera looks at target
local MIN_CAMERA_DISTANCE = 1 -- Minimum distance from player when colliding

type CameraControllerType = {
	player: Player,
	camera: Camera,
	enabled: boolean,
	heartbeatConnection: RBXScriptConnection?,
	originalCameraType: Enum.CameraType,
	targetLookPosition: Vector3?,
	enable: (self: CameraControllerType) -> (),
	disable: (self: CameraControllerType) -> (),
	setTargetLookPosition: (self: CameraControllerType, position: Vector3?) -> (),
	tweenToPosition: (self: CameraControllerType, targetCFrame: CFrame, duration: number?) -> Tween,
	_updateCamera: (self: CameraControllerType) -> (),
	_getIdealCameraPosition: (self: CameraControllerType) -> Vector3,
	_checkCollision: (self: CameraControllerType, startPos: Vector3, endPos: Vector3) -> Vector3,
	_getLookAtPosition: (self: CameraControllerType) -> Vector3,
	_startUpdateLoop: (self: CameraControllerType) -> (),
	_stopUpdateLoop: (self: CameraControllerType) -> (),
	destroy: (self: CameraControllerType) -> (),
}

local CameraController_Instance = nil

function CameraController.new()
	if CameraController_Instance then
		return CameraController_Instance
	end

	local self = setmetatable({}, CameraController) :: any
	CameraController_Instance = self

	self.player = Players.LocalPlayer
	self.camera = Workspace.CurrentCamera
	self.enabled = false
	self.heartbeatConnection = nil
	self.originalCameraType = self.camera.CameraType
	self.targetLookPosition = nil

	return self
end

-- Enable over-the-shoulder camera
function CameraController:enable()
	if self.enabled then
		return
	end

	self.enabled = true
	self.camera.CameraType = Enum.CameraType.Scriptable

	self:_startUpdateLoop()

	print("📷 CameraController: Over-the-shoulder camera enabled")
end

-- Disable and return to normal camera
function CameraController:disable()
	if not self.enabled then
		return
	end

	self.enabled = false
	self:_stopUpdateLoop()

	self.camera.CameraType = self.originalCameraType

	print("📷 CameraController: Camera control disabled")
end

-- Set a specific position for the camera to look at (optional override)
function CameraController:setTargetLookPosition(position: Vector3?)
	self.targetLookPosition = position
end

-- Tween camera to a specific position (useful for cutscenes)
function CameraController:tweenToPosition(targetCFrame: CFrame, duration: number?): Tween
	duration = duration or 1

	local tween = TweenService:Create(
		self.camera,
		TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ CFrame = targetCFrame }
	)

	tween:Play()
	return tween
end

-- Get the ideal camera position based on player position
function CameraController:_getIdealCameraPosition(): Vector3
	local character = self.player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then
		return self.camera.CFrame.Position
	end

	local rootPart = character.HumanoidRootPart :: BasePart
	local playerCFrame = rootPart.CFrame :: CFrame

	-- Calculate camera position relative to player orientation
	local idealPosition = (playerCFrame * CFrame.new(CAMERA_OFFSET)).Position

	-- Check for collisions and adjust if necessary
	local playerPosition = rootPart.Position
	local finalPosition = self:_checkCollision(playerPosition, idealPosition)

	return finalPosition
end

-- Check for obstacles between player and camera position
function CameraController:_checkCollision(startPos: Vector3, endPos: Vector3): Vector3
	local direction = (endPos - startPos).Unit
	local distance = (endPos - startPos).Magnitude

	-- Perform raycast to check for obstacles
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { self.player.Character }

	local raycastResult = Workspace:Raycast(startPos, direction * distance, raycastParams)

	if raycastResult then
		-- Obstacle found, move camera closer to player
		local obstructionPoint = raycastResult.Position
		local safeDistance = math.max((obstructionPoint - startPos).Magnitude - 0.5, MIN_CAMERA_DISTANCE)
		return startPos + direction * safeDistance
	end

	-- No obstruction, use ideal position
	return endPos
end

-- Get the position the camera should look at
function CameraController:_getLookAtPosition(): Vector3
	-- Use override position if set
	if self.targetLookPosition then
		return self.targetLookPosition
	end

	-- Try to get GUI position from WorldGUIManager
	local worldGUIManager = WorldGUIManager.getInstance()
	if worldGUIManager then
		local guiPosition = worldGUIManager:getGUIPosition()
		if guiPosition and guiPosition.Magnitude > 0 then
			return guiPosition
		end
	end

	-- Fallback: look at player's head/upper torso
	local character = self.player.Character
	if not character then
		return Vector3.new(0, 0, 0)
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if humanoidRootPart then
		-- Look slightly above the player (at head level)
		return humanoidRootPart.Position + Vector3.new(0, 1.5, 0)
	end

	return Vector3.new(0, 0, 0)
end

-- Main camera update function
function CameraController:_updateCamera()
	if not self.enabled then
		return
	end

	local idealPosition = self:_getIdealCameraPosition()
	local lookAtPosition = self:_getLookAtPosition()

	-- Smooth interpolation
	local currentPosition = self.camera.CFrame.Position
	local newPosition = currentPosition:Lerp(idealPosition, FOLLOW_SMOOTHNESS)

	-- Create new camera CFrame looking at target
	local newCFrame = CFrame.lookAt(newPosition, lookAtPosition)

	-- Smooth rotation interpolation
	local currentCFrame = self.camera.CFrame
	local finalCFrame = currentCFrame:Lerp(newCFrame, LOOK_SMOOTHNESS)

	self.camera.CFrame = finalCFrame
end

-- Start the camera update loop
function CameraController:_startUpdateLoop()
	if self.heartbeatConnection then
		self.heartbeatConnection:Disconnect()
	end

	self.heartbeatConnection = RunService.Heartbeat:Connect(function()
		self:_updateCamera()
	end)
end

-- Stop the camera update loop
function CameraController:_stopUpdateLoop()
	if self.heartbeatConnection then
		self.heartbeatConnection:Disconnect()
	end
	(self :: any).heartbeatConnection = nil
end

-- Cleanup
function CameraController:destroy()
	self:disable()
	self:_stopUpdateLoop()
	CameraController_Instance = nil :: any
end

-- Get the singleton instance
function CameraController.getInstance()
	return CameraController_Instance or CameraController.new()
end

return CameraController
