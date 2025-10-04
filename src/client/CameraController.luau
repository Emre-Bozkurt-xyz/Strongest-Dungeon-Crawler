--!strict
-- CameraController: toggles between Over-the-Shoulder (shift-lock style) and Roblox default (free) camera,
-- while enforcing sensible zoom limits and respecting character respawns.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local WorldGUIManager = require(script.Parent.WorldGUIManager)

local CameraController = {}
CameraController.__index = CameraController

-- Configuration
-- Over-shoulder defaults: lateral (right), up, and back distance from the player
local SHOULDER_RIGHT = 2.0
local SHOULDER_UP = 2.75
local SHOULDER_BACK = 6.0
local FOLLOW_SMOOTHNESS = 0.5 -- How smoothly camera follows player (0-1)
local LOOK_SMOOTHNESS = 0.15 -- How smoothly camera looks at target
local MIN_CAMERA_DISTANCE = 1 -- Minimum distance from player when colliding

local DEFAULT_MIN_ZOOM = 2.5 -- don't let players zoom into the face
local DEFAULT_MAX_ZOOM = 16
local LOOK_FORWARD_DISTANCE = 25
local LOOK_UP_OFFSET_Y = 1.5
local _FOCUS_DISTANCE = 6.0
local _FOCUS_UP = 0.5
local _FOCUS_TWEEN = 0.3

-- Mouse-look configuration (Over-Shoulder)
local MOUSE_SENS_YAW = 0.0025
local MOUSE_SENS_PITCH = 0.0020
local PITCH_MIN = math.rad(-45)
local PITCH_MAX = math.rad(35)

export type Mode = "Free" | "OverShoulder"

type CameraControllerType = {
	player: Player,
	camera: Camera,
	enabled: boolean,
	mode: Mode,
	heartbeatConnection: RBXScriptConnection?,
	originalCameraType: Enum.CameraType,
	targetLookPosition: Vector3?,
	minZoom: number,
	maxZoom: number,

	-- Cursor lock state and API
	isCursorUnlocked: (self: CameraControllerType) -> boolean,
	setCursorUnlocked: (self: CameraControllerType, unlocked: boolean) -> (),
	toggleCursorUnlocked: (self: CameraControllerType) -> (),

	setMode: (self: CameraControllerType, mode: Mode) -> (),
	toggleMode: (self: CameraControllerType) -> (),
	setZoomLimits: (self: CameraControllerType, minZoom: number, maxZoom: number) -> (),
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
	focusOn: (self: CameraControllerType, target: BasePart, tweenTime: number?) -> (),
	clearFocus: (self: CameraControllerType) -> (),
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
	self.mode = "OverShoulder"
	self.heartbeatConnection = nil
	self._inputConn = nil
	self.originalCameraType = self.camera.CameraType
	self.targetLookPosition = nil
	self.minZoom = DEFAULT_MIN_ZOOM
	self.maxZoom = DEFAULT_MAX_ZOOM
	self._isFocusing = false
	self._savedCamCF = nil
	self._focusTarget = nil
	self._yaw = 0
	self._pitch = 0
	self._cursorUnlocked = false

	-- Enforce zoom limits for Free camera
	self.player.CameraMinZoomDistance = self.minZoom
	self.player.CameraMaxZoomDistance = self.maxZoom

	return self
end

function CameraController:setZoomLimits(minZoom: number, maxZoom: number)
	self.minZoom = minZoom
	self.maxZoom = maxZoom
	self.player.CameraMinZoomDistance = minZoom
	self.player.CameraMaxZoomDistance = maxZoom
end

function CameraController:setMode(mode: Mode)
	self.mode = mode
	if not self.enabled then
		return
	end

	if mode == "Free" then
		-- Default Roblox camera, keep zoom limits
		self.camera.CameraType = Enum.CameraType.Custom
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		-- Restore character auto-rotate
		local hum = self.player.Character and self.player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.AutoRotate = true
		end
		-- Panels: follow camera in Free mode
		local wg = WorldGUIManager.getInstance()
		if wg then
			wg:setPanelFollowMode("SystemPanel", "camera")
			wg:setPanelCameraSpaceOffset("SystemPanel", Vector3.new(0, 0.0, 0.0))
		end
		if self.heartbeatConnection then
			self.heartbeatConnection:Disconnect()
			local s: any = self
			s.heartbeatConnection = nil
		end
		if self._inputConn then
			self._inputConn:Disconnect()
			local s2: any = self
			s2._inputConn = nil
		end
		return
	end

	-- Over-Shoulder
	self.camera.CameraType = Enum.CameraType.Scriptable
	-- Apply cursor state for OS mode
	if self._cursorUnlocked then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = false
	end
	-- Initialize yaw/pitch from current camera facing relative to character
	local hrp = self.player.Character and self.player.Character:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		local look = (self.camera.CFrame.LookVector)
		-- derive yaw from camera forward projected on XZ
		local flatForward = Vector3.new(look.X, 0, look.Z)
		if flatForward.Magnitude > 0.001 then
			self._yaw = math.atan2(-flatForward.X, -flatForward.Z)
		end
		-- derive pitch from camera forward Y
		self._pitch = math.clamp(math.asin(math.clamp(look.Y, -1, 1)), PITCH_MIN, PITCH_MAX)
	end
	-- Panels: keep following camera in OS mode as well for consistency
	local wg2 = WorldGUIManager.getInstance()
	if wg2 then
		wg2:setPanelFollowMode("SystemPanel", "camera")
		wg2:setPanelCameraSpaceOffset("SystemPanel", Vector3.new(0, 0.0, 0.0))
	end
	-- Disable character auto-rotate; we will orient to camera yaw
	local hum2 = self.player.Character and self.player.Character:FindFirstChildOfClass("Humanoid")
	if hum2 then
		hum2.AutoRotate = false
	end
	if self.heartbeatConnection then
		self.heartbeatConnection:Disconnect()
		local s: any = self
		s.heartbeatConnection = nil
	end
	-- Mouse delta -> yaw/pitch
	if self._inputConn then
		self._inputConn:Disconnect()
		local s3: any = self
		s3._inputConn = nil
	end
	self._inputConn = UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			-- Ignore mouse deltas while cursor is unlocked for UI interaction in OS mode
			if not self._cursorUnlocked then
				local d = input.Delta
				self._yaw += -d.X * MOUSE_SENS_YAW
				self._pitch = math.clamp(self._pitch + -d.Y * MOUSE_SENS_PITCH, PITCH_MIN, PITCH_MAX)
			end
		end
	end)
	self:_startUpdateLoop()
end

function CameraController:isCursorUnlocked(): boolean
	return (self :: any)._cursorUnlocked == true
end

function CameraController:setCursorUnlocked(unlocked: boolean)
	(self :: any)._cursorUnlocked = unlocked and true or false
	-- Apply immediately if currently in Over-Shoulder mode
	if self.enabled and self.mode == "OverShoulder" then
		if (self :: any)._cursorUnlocked then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		else
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
			UserInputService.MouseIconEnabled = false
		end
	end
end

function CameraController:toggleCursorUnlocked()
	self:setCursorUnlocked(not self:isCursorUnlocked())
end

function CameraController:toggleMode()
	if self.mode == "Free" then
		self:setMode("OverShoulder")
	else
		self:setMode("Free")
	end
end

-- Enable over-the-shoulder camera
function CameraController:enable()
	if self.enabled then
		return
	end

	self.enabled = true
	self:setMode(self.mode)

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
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true

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
	local rootPos = rootPart.Position
	-- Build camera rotation from yaw/pitch
	local camRot = CFrame.Angles(0, self._yaw, 0) * CFrame.Angles(self._pitch, 0, 0)
	local offsetWorld = camRot:VectorToWorldSpace(Vector3.new(SHOULDER_RIGHT, SHOULDER_UP, SHOULDER_BACK))
	local idealPosition = rootPos + offsetWorld

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
	-- Exclude the player's character and any world-space UI panels so the camera doesn't
	-- treat them as obstacles (prevents jitter/feedback when a panel is near the camera)
	local exclude: { Instance } = {}
	if self.player.Character then
		table.insert(exclude, self.player.Character)
	end
	local wg = WorldGUIManager.getInstance()
	if wg and (wg :: any).getPanelParts then
		local parts = (wg :: any):getPanelParts()
		for _, inst in ipairs(parts) do
			table.insert(exclude, inst)
		end
	end
	raycastParams.FilterDescendantsInstances = exclude

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

	-- If focusing on a specific target in OverShoulder, aim at that target
	local s: any = self
	if s._isFocusing and self.mode == "OverShoulder" then
		local ft: BasePart? = s._focusTarget
		if ft then
			-- Clamp vertical look so we don't drift into upward arcs
			local char = self.player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp and hrp:IsA("BasePart") then
				local headY = (hrp :: BasePart).Position.Y + LOOK_UP_OFFSET_Y
				local p = ft.Position
				return Vector3.new(p.X, headY, p.Z)
			end
			return ft.Position
		end
	end

	-- Over-shoulder: look forward in the same direction as the player, not at the head
	local character = self.player.Character
	if not character then
		return Vector3.new(0, 0, 0)
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if humanoidRootPart then
		local pos = humanoidRootPart.Position
		-- Camera forward from yaw/pitch
		local camForward = (CFrame.Angles(0, self._yaw, 0) * CFrame.Angles(self._pitch, 0, 0)).LookVector
		return pos + camForward * LOOK_FORWARD_DISTANCE + Vector3.new(0, LOOK_UP_OFFSET_Y, 0)
	end

	-- As a last resort, if we have WorldGUIManager and we couldn't find HRP, try its target
	local worldGUIManager = WorldGUIManager.getInstance()
	if worldGUIManager then
		local guiPosition = worldGUIManager:getGUIPosition()
		if guiPosition and guiPosition.Magnitude > 0 then
			return guiPosition
		end
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
		if self.mode ~= "OverShoulder" then
			return
		end
		self:_updateCamera()
		-- Orient character to camera yaw so movement is camera-relative and mouse controls facing
		local character = self.player.Character
		local hrpAny = character and character:FindFirstChild("HumanoidRootPart")
		local hum = character and character:FindFirstChildOfClass("Humanoid")
		if hrpAny and hrpAny:IsA("BasePart") and hum then
			local hrp = hrpAny :: BasePart
			local pos = hrp.Position
			local desired = CFrame.new(pos) * CFrame.Angles(0, self._yaw, 0)
			hrp.CFrame = desired
		end
	end)
end

-- Stop the camera update loop
function CameraController:_stopUpdateLoop()
	if self.heartbeatConnection then
		self.heartbeatConnection:Disconnect()
	end
	(self :: any).heartbeatConnection = nil
	if self._inputConn then
		self._inputConn:Disconnect()
		local s4: any = self
		s4._inputConn = nil
	end
end

-- Focus the camera on a target part (e.g., System Panel) and free the mouse for UI.
function CameraController:focusOn(target: BasePart, _tweenTime: number?)
	if not target then
		return
	end
	local s: any = self
	s._isFocusing = true
	if self.mode == "OverShoulder" then
		s._focusTarget = target
		-- Ensure panel is anchored to player during OS focus to avoid camera-follow feedback loops
		local wg = WorldGUIManager.getInstance()
		if wg then
			wg:setPanelFollowMode("SystemPanel", "player")
		end
	end
	-- In Free mode, do nothing special; panel remains readable via its own placement.
end

-- Clear focus and restore previous OS camera behavior
function CameraController:clearFocus()
	local s: any = self
	s._isFocusing = false
	s._focusTarget = nil
	if self.mode == "OverShoulder" then
		local wg = WorldGUIManager.getInstance()
		if wg then
			wg:setPanelFollowMode("SystemPanel", "camera")
		end
	end
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
