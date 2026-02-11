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

local BASE_FOV = 70

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
	_modifierId: number,
	_modifiers: { [string]: any },
	_lockYaw: boolean,
	_lockPitch: boolean,
	_yawAssist: number,
	_lookAtProvider: (() -> Vector3?)?,

	_computeOverrides: (self: CameraControllerType) -> CameraSettings,

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
	pushModifier: (self: CameraControllerType, spec: { [string]: any }) -> string,
	popModifier: (self: CameraControllerType, id: string) -> (),
	clearModifiers: (self: CameraControllerType) -> (),
	_updateCamera: (self: CameraControllerType) -> (),
	_getIdealCameraPosition: (self: CameraControllerType, settings: { [string]: any }, yawOverride: number?, pitchOverride: number?) -> Vector3,
	_checkCollision: (self: CameraControllerType, startPos: Vector3, endPos: Vector3) -> Vector3,
	_getLookAtPosition: (self: CameraControllerType) -> Vector3,
	_startUpdateLoop: (self: CameraControllerType) -> (),
	_stopUpdateLoop: (self: CameraControllerType) -> (),
	focusOn: (self: CameraControllerType, target: BasePart, tweenTime: number?) -> (),
	clearFocus: (self: CameraControllerType) -> (),
	destroy: (self: CameraControllerType) -> (),
}

type CameraShake = {
	strength: number?,
	frequency: number?,
}

type CameraSettings = {
	shoulderRight: number,
	shoulderUp: number,
	shoulderBack: number,
	followSmoothness: number,
	lookSmoothness: number,
	fov: number,
	lockYaw: boolean,
	lockPitch: boolean,
	shake: CameraShake?,
	yawAssist: { maxYaw: number, deadzone: number, smoothness: number }?,
	lookAtProvider: (() -> Vector3?)?,
}

type CameraModifierSpec = {
	priority: number?,
	duration: number?,
	shoulderOffset: Vector3?,
	shoulderRight: number?,
	shoulderUp: number?,
	shoulderBack: number?,
	followSmoothness: number?,
	lookSmoothness: number?,
	fov: number?,
	lockYaw: boolean?,
	lockPitch: boolean?,
	shake: CameraShake?,
	yawAssist: { maxYaw: number, deadzone: number, smoothness: number }?,
	lookAtProvider: (() -> Vector3?)?,
}

type CameraModifierEntry = {
	id: string,
	spec: CameraModifierSpec,
	priority: number,
	expiresAt: number?,
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
	self._lookAtProvider = nil
	self._yaw = 0
	self._pitch = 0
	self._cursorUnlocked = false
	self._modifierId = 0
	self._modifiers = {} :: { [string]: CameraModifierEntry }
	self._lockYaw = false
	self._lockPitch = false
	self._yawAssist = 0
	self.camera.FieldOfView = BASE_FOV

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
			if not self._cursorUnlocked and not self._lockYaw then
				local d = input.Delta
				self._yaw += -d.X * MOUSE_SENS_YAW
				if not self._lockPitch then
					self._pitch = math.clamp(self._pitch + -d.Y * MOUSE_SENS_PITCH, PITCH_MIN, PITCH_MAX)
				end
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

function CameraController:pushModifier(spec: CameraModifierSpec): string
	self._modifierId += 1
	local id = `cam_mod_{self._modifierId}`
	local duration = spec.duration
	self._modifiers[id] = {
		id = id,
		spec = spec,
		priority = spec.priority or 0,
		expiresAt = duration and (os.clock() + duration) or nil,
	}
	return id
end

function CameraController:popModifier(id: string)
	self._modifiers[id] = nil
end

function CameraController:clearModifiers()
	self._modifiers = {}
end

function CameraController:_computeOverrides(): CameraSettings
	local now = os.clock()
	local ordered: { CameraModifierEntry } = {}
	for key, entry in pairs(self._modifiers) do
		if entry.expiresAt and now >= entry.expiresAt then
			self._modifiers[key] = nil
		else
			table.insert(ordered, entry)
		end
	end
	table.sort(ordered, function(a, b)
		return (a.priority or 0) < (b.priority or 0)
	end)

	local settings = {
		shoulderRight = SHOULDER_RIGHT,
		shoulderUp = SHOULDER_UP,
		shoulderBack = SHOULDER_BACK,
		followSmoothness = FOLLOW_SMOOTHNESS,
		lookSmoothness = LOOK_SMOOTHNESS,
		fov = BASE_FOV,
		lockYaw = false,
		lockPitch = false,
		shake = nil,
		yawAssist = nil,
		lookAtProvider = nil,
	}

	for _, entry in ipairs(ordered) do
		local spec = entry.spec or {}
		if spec.shoulderOffset then
			settings.shoulderRight = spec.shoulderOffset.X
			settings.shoulderUp = spec.shoulderOffset.Y
			settings.shoulderBack = spec.shoulderOffset.Z
		end
		if spec.shoulderRight ~= nil then
			settings.shoulderRight = spec.shoulderRight
		end
		if spec.shoulderUp ~= nil then
			settings.shoulderUp = spec.shoulderUp
		end
		if spec.shoulderBack ~= nil then
			settings.shoulderBack = spec.shoulderBack
		end
		if spec.followSmoothness ~= nil then
			settings.followSmoothness = spec.followSmoothness
		end
		if spec.lookSmoothness ~= nil then
			settings.lookSmoothness = spec.lookSmoothness
		end
		if spec.fov ~= nil then
			settings.fov = spec.fov
		end
		if spec.lockYaw ~= nil then
			settings.lockYaw = spec.lockYaw
		end
		if spec.lockPitch ~= nil then
			settings.lockPitch = spec.lockPitch
		end
		if spec.shake ~= nil then
			settings.shake = spec.shake
		end
		if spec.yawAssist ~= nil then
			settings.yawAssist = spec.yawAssist
		end
		if spec.lookAtProvider ~= nil then
			settings.lookAtProvider = spec.lookAtProvider
		end
	end

	return settings
end

-- Get the ideal camera position based on player position
function CameraController:_getIdealCameraPosition(settings: CameraSettings, yawOverride: number?, pitchOverride: number?): Vector3
	local character = self.player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then
		return self.camera.CFrame.Position
	end

	local rootPart = character.HumanoidRootPart :: BasePart
	local rootPos = rootPart.Position
	-- Build camera rotation from yaw/pitch
	local yaw = yawOverride or self._yaw
	local pitch = pitchOverride or self._pitch
	local camRot = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
	local offsetWorld =
		camRot:VectorToWorldSpace(Vector3.new(settings.shoulderRight, settings.shoulderUp, settings.shoulderBack))
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

	if self._lookAtProvider then
		local pos = self._lookAtProvider()
		if pos then
			local char = self.player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp and hrp:IsA("BasePart") then
				local headY = (hrp :: BasePart).Position.Y + LOOK_UP_OFFSET_Y
				return Vector3.new(pos.X, headY, pos.Z)
			end
			return pos
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

	local settings = self:_computeOverrides()
	self._lockYaw = settings.lockYaw
	self._lockPitch = settings.lockPitch
	self.camera.FieldOfView = settings.fov
	self._lookAtProvider = settings.lookAtProvider

	local yawOffset = 0
	if settings.yawAssist then
		local assist = settings.yawAssist
		local viewport = self.camera.ViewportSize
		if viewport.X > 0 then
			local mousePos = UserInputService:GetMouseLocation()
			local centerX = viewport.X * 0.5
			local normalized = (mousePos.X - centerX) / centerX
			if math.abs(normalized) < assist.deadzone then
				normalized = 0
			else
				local sign = normalized >= 0 and 1 or -1
				normalized = sign * (math.abs(normalized) - assist.deadzone) / (1 - assist.deadzone)
			end
			local targetOffset = math.clamp(normalized, -1, 1) * assist.maxYaw
			local smooth = assist.smoothness or 0.2
			local current = self._yawAssist or 0
			self._yawAssist = current + (targetOffset - current) * math.clamp(smooth, 0, 1)
			yawOffset = self._yawAssist
		end
	else
		self._yawAssist = 0
	end

	local idealPosition = self:_getIdealCameraPosition(settings, self._yaw + yawOffset, self._pitch)
	local lookAtPosition = self:_getLookAtPosition()

	-- Smooth interpolation
	local currentPosition = self.camera.CFrame.Position
	local newPosition = currentPosition:Lerp(idealPosition, settings.followSmoothness)

	-- Create new camera CFrame looking at target
	local newCFrame = CFrame.lookAt(newPosition, lookAtPosition)

	-- Smooth rotation interpolation
	local currentCFrame = self.camera.CFrame
	local finalCFrame = (currentCFrame:Lerp(newCFrame, settings.lookSmoothness)) :: CFrame

	if settings.shake then
		local strength = settings.shake.strength or 0
		local frequency = settings.shake.frequency or 20
		if strength > 0 then
			local t = os.clock() * frequency
			local offset = Vector3.new(
				(math.noise(t, 0, 0) - 0.5) * 2,
				(math.noise(0, t, 0) - 0.5) * 2,
				(math.noise(0, 0, t) - 0.5) * 2
			) * strength
			finalCFrame = finalCFrame + offset
		end
	end

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
			if hrp:GetAttribute("ExternalFacing") == true then
				return
			end
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
