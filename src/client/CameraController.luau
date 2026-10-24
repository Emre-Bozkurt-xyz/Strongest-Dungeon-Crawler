--!strict
-- CameraController: toggles between Over-the-Shoulder (shift-lock style) and Roblox default (free) camera,
-- while enforcing sensible zoom limits and respecting character respawns.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local WorldGUIManager = require(script.Parent.WorldGUIManager)
local CharacterFacingController = require(script.Parent.CharacterFacingController)
local SharedConfig = require(ReplicatedStorage.Shared.Config)
local DevTuningService = require(script.Parent.dev.DevTuningService)
local Ease = require(ReplicatedStorage.Shared.ui.Ease)

local CameraController = {}
CameraController.__index = CameraController

local CameraConfig = SharedConfig.Camera
local CAMERA_BASELINE = CameraConfig.baseline
-- Configuration
-- Over-shoulder defaults: lateral (right), up, and back distance from the player
local SHOULDER_RIGHT = CAMERA_BASELINE.shoulderRight
local SHOULDER_UP = CAMERA_BASELINE.shoulderUp
local SHOULDER_BACK = CAMERA_BASELINE.shoulderBack
local FOLLOW_SMOOTHNESS = CAMERA_BASELINE.followSmoothness -- How smoothly camera follows player (0-1)
local LOOK_SMOOTHNESS = CAMERA_BASELINE.lookSmoothness -- How smoothly camera looks at target
local MIN_CAMERA_DISTANCE = CAMERA_BASELINE.minCameraDistance -- Minimum distance from player when colliding

local DEFAULT_MIN_ZOOM = CAMERA_BASELINE.defaultMinZoom -- don't let players zoom into the face
local DEFAULT_MAX_ZOOM = CAMERA_BASELINE.defaultMaxZoom
local LOOK_FORWARD_DISTANCE = CAMERA_BASELINE.lookForwardDistance
local LOOK_UP_OFFSET_Y = CAMERA_BASELINE.lookUpOffsetY
local _FOCUS_DISTANCE = CAMERA_BASELINE.focus.distance
local _FOCUS_UP = CAMERA_BASELINE.focus.up
local _FOCUS_TWEEN = CAMERA_BASELINE.focus.tween

local BASE_FOV = CAMERA_BASELINE.baseFov

-- Mouse-look configuration (Over-Shoulder)
local MOUSE_SENS_YAW = CAMERA_BASELINE.mouseSensYaw
local MOUSE_SENS_PITCH = CAMERA_BASELINE.mouseSensPitch
local PITCH_MIN = CAMERA_BASELINE.pitchMin
local PITCH_MAX = CAMERA_BASELINE.pitchMax

local function num(path: string, fallback: number): number
	local v = DevTuningService.get(path)
	return if type(v) == "number" then v else fallback
end

local function notifyInteractionCameraMode(mode: Mode)
	local ok, InteractionStateController = pcall(require, script.Parent.input.InteractionStateController)
	if ok and InteractionStateController and InteractionStateController.setCameraMode then
		InteractionStateController.setCameraMode(mode)
	end
end

local function applyBaselineTuning()
	SHOULDER_RIGHT = num("Camera.baseline.shoulderRight", CAMERA_BASELINE.shoulderRight)
	SHOULDER_UP = num("Camera.baseline.shoulderUp", CAMERA_BASELINE.shoulderUp)
	SHOULDER_BACK = num("Camera.baseline.shoulderBack", CAMERA_BASELINE.shoulderBack)
	FOLLOW_SMOOTHNESS = num("Camera.baseline.followSmoothness", CAMERA_BASELINE.followSmoothness)
	LOOK_SMOOTHNESS = num("Camera.baseline.lookSmoothness", CAMERA_BASELINE.lookSmoothness)
	MIN_CAMERA_DISTANCE = num("Camera.baseline.minCameraDistance", CAMERA_BASELINE.minCameraDistance)
	DEFAULT_MIN_ZOOM = num("Camera.baseline.defaultMinZoom", CAMERA_BASELINE.defaultMinZoom)
	DEFAULT_MAX_ZOOM = num("Camera.baseline.defaultMaxZoom", CAMERA_BASELINE.defaultMaxZoom)
	LOOK_FORWARD_DISTANCE = num("Camera.baseline.lookForwardDistance", CAMERA_BASELINE.lookForwardDistance)
	LOOK_UP_OFFSET_Y = num("Camera.baseline.lookUpOffsetY", CAMERA_BASELINE.lookUpOffsetY)
	_FOCUS_DISTANCE = num("Camera.baseline.focus.distance", CAMERA_BASELINE.focus.distance)
	_FOCUS_UP = num("Camera.baseline.focus.up", CAMERA_BASELINE.focus.up)
	_FOCUS_TWEEN = num("Camera.baseline.focus.tween", CAMERA_BASELINE.focus.tween)
	BASE_FOV = num("Camera.baseline.baseFov", CAMERA_BASELINE.baseFov)
	MOUSE_SENS_YAW = num("Camera.baseline.mouseSensYaw", CAMERA_BASELINE.mouseSensYaw)
	MOUSE_SENS_PITCH = num("Camera.baseline.mouseSensPitch", CAMERA_BASELINE.mouseSensPitch)
	PITCH_MIN = num("Camera.baseline.pitchMin", CAMERA_BASELINE.pitchMin)
	PITCH_MAX = num("Camera.baseline.pitchMax", CAMERA_BASELINE.pitchMax)
end

applyBaselineTuning()
DevTuningService.subscribe("Camera.baseline", function()
	applyBaselineTuning()
end)

export type Mode = "Free" | "OverShoulder"

type CameraControllerType = {
	player: Player,
	camera: Camera,
	enabled: boolean,
	mode: Mode,
	updateLoopBound: boolean,
	originalCameraType: Enum.CameraType,
	targetLookPosition: Vector3?,
	minZoom: number,
	maxZoom: number,
	_modifierId: number,
	_modifiers: { [string]: any },
	_lockYaw: boolean,
	_lockPitch: boolean,
	_yawAssist: number,
	_poseMove: PoseMove?,
	_release: PoseRelease?,
	_stagedLoopBound: boolean?,
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
	setAngles: (self: CameraControllerType, yaw: number?, pitch: number?) -> (),
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

-- A whole camera pose from a staged view. The camera travels to it in a fixed `duration` eased to a
-- hard stop -- an exponential settle's long tail is what made the menu camera feel floaty -- then
-- holds it exactly. A change of `key` (another view) starts a new move from wherever the camera is.
-- `releaseDuration` is the matching move back to gameplay when the pose goes away.
type StagedPose = {
	cframe: CFrame,
	fov: number?,
	duration: number?,
	releaseDuration: number?,
	key: any?,
}

type PoseMove = {
	from: CFrame,
	fromFov: number,
	started: number,
	key: any?,
	releaseDuration: number,
}

type PoseRelease = {
	from: CFrame,
	fromFov: number,
	started: number,
	duration: number,
}

local DEFAULT_POSE_DURATION = 0.3
local DEFAULT_RELEASE_DURATION = 0.22
local RELEASE_RENDER_STEP_NAME = "StrongestDungeonCrawler.CameraController.Release"
local RELEASE_RESTORE_STEP_NAME = "StrongestDungeonCrawler.CameraController.ReleaseRestore"

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
	poseProvider: (() -> StagedPose?)?,
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
	-- Supplies the whole camera pose, bypassing shoulder offsets, look-at and collision. For a staged
	-- view (the menu) whose owner has already solved where the camera belongs.
	poseProvider: (() -> StagedPose?)?,
}

type CameraModifierEntry = {
	id: string,
	spec: CameraModifierSpec,
	priority: number,
	expiresAt: number?,
}

local CameraController_Instance = nil
local CAMERA_RENDER_STEP_NAME = "StrongestDungeonCrawler.CameraController"
local STAGED_RENDER_STEP_NAME = "StrongestDungeonCrawler.CameraController.Staged"

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
	self.updateLoopBound = false
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
	notifyInteractionCameraMode(mode)
	if not self.enabled then
		CharacterFacingController.getInstance():setCameraMode(mode)
		return
	end

	if mode == "Free" then
		-- Default Roblox camera, keep zoom limits
		self.camera.CameraType = Enum.CameraType.Custom
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
		CharacterFacingController.getInstance():setCameraMode(mode)
		-- Panel follow modes are owned by the UI layer (PanelRegistry placement), not the camera.
		self:_stopUpdateLoop()
		if self._inputConn then
			self._inputConn:Disconnect()
			local s2: any = self
			s2._inputConn = nil
		end
		self:_syncStagedLoop()
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
	CharacterFacingController.getInstance():setCameraMode(mode)
	CharacterFacingController.getInstance():applyCameraYaw(self._yaw)
	-- Panel follow modes are owned by the UI layer (PanelRegistry placement), not the camera.
	self:_stopUpdateLoop()
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
	self:_syncStagedLoop()
end

function CameraController:isCursorUnlocked(): boolean
	return (self :: any)._cursorUnlocked == true
end

function CameraController:setCursorUnlocked(unlocked: boolean)
	local selfAny = self :: any
	selfAny._cursorUnlocked = unlocked and true or false
	-- Apply immediately if currently in Over-Shoulder mode
	if self.enabled and self.mode == "OverShoulder" then
		if selfAny._cursorUnlocked then
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
	self:_syncStagedLoop()

	self.camera.CameraType = self.originalCameraType
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	notifyInteractionCameraMode("Free")
	CharacterFacingController.getInstance():setCameraMode("Free")
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
	self:_syncStagedLoop()
	return id
end

function CameraController:popModifier(id: string)
	self._modifiers[id] = nil
	-- A staged pose ending hands back to gameplay with a move of its own rather than a cut.
	local posed = false
	for _, entry in pairs(self._modifiers) do
		if entry.spec.poseProvider then
			posed = true
			break
		end
	end
	if not posed and self._poseMove then
		self._release = {
			from = self.camera.CFrame,
			fromFov = self.camera.FieldOfView,
			started = os.clock(),
			duration = self._poseMove.releaseDuration,
		}
		self._poseMove = nil
	end
	self:_syncStagedLoop()
end

-- Eased progress of the move back to gameplay, or nil once it has finished.
function CameraController:_releaseProgress(): (PoseRelease?, number)
	local release = self._release
	if not release then
		return nil, 1
	end
	local t = if release.duration > 0 then math.clamp((os.clock() - release.started) / release.duration, 0, 1) else 1
	if t >= 1 then
		self._release = nil
		return nil, 1
	end
	return release, Ease.quartOut(t)
end

-- Moves the camera toward a staged pose if a modifier supplies one; false when none does.
function CameraController:_applyStagedPose(settings: CameraSettings): boolean
	local posed = settings.poseProvider and settings.poseProvider()
	if not posed then
		return false
	end
	-- A fixed-time move from where the camera was to the pose, restarted when the view changes. The
	-- pose is re-read every frame, so after arriving the camera holds it exactly. _yaw and _pitch are
	-- left untouched, so the gameplay camera resumes exactly where it was when the pose goes away.
	local now = os.clock()
	local move = self._poseMove
	if not move or move.key ~= posed.key then
		move = {
			from = self.camera.CFrame,
			fromFov = self.camera.FieldOfView,
			started = now,
			key = posed.key,
			releaseDuration = posed.releaseDuration or DEFAULT_RELEASE_DURATION,
		}
		self._poseMove = move
		self._release = nil
	end
	local duration = posed.duration or DEFAULT_POSE_DURATION
	local t = if duration > 0 then math.clamp((now - move.started) / duration, 0, 1) else 1
	-- Quart rather than expo: still lands hard, without the first-frame lurch that reads as a cut.
	local eased = Ease.quartOut(t)
	self.camera.CFrame = move.from:Lerp(posed.cframe, eased)
	local fov = posed.fov or settings.fov
	self.camera.FieldOfView = move.fromFov + (fov - move.fromFov) * eased
	return true
end

-- A staged pose has to win in both camera modes. Over-shoulder already runs our loop, which checks
-- for one first. Free mode hands the camera to Roblox's own controller and runs no loop of ours, so
-- while a pose is active the camera is taken back as Scriptable and driven by a loop of its own,
-- then returned to Roblox when the pose goes away.
function CameraController:_syncStagedLoop()
	local staged = false
	for _, entry in pairs(self._modifiers) do
		if entry.spec.poseProvider then
			staged = true
			break
		end
	end
	local wanted = staged and self.enabled and self.mode == "Free"

	if wanted and not self._stagedLoopBound then
		self._stagedLoopBound = true
		self._poseMove = nil
		self.camera.CameraType = Enum.CameraType.Scriptable
		RunService:BindToRenderStep(STAGED_RENDER_STEP_NAME, Enum.RenderPriority.Camera.Value, function()
			self:_applyStagedPose(self:_computeOverrides())
		end)
	elseif not wanted and self._stagedLoopBound then
		self._stagedLoopBound = false
		RunService:UnbindFromRenderStep(STAGED_RENDER_STEP_NAME)
		if self.enabled and self.mode == "Free" then
			self.camera.CameraType = Enum.CameraType.Custom
			-- Roblox's own camera never touches FieldOfView, so the staged one would stick.
			local fov = self:_computeOverrides().fov
			self.camera.FieldOfView = fov
			-- Roblox's camera computes its own pose each frame; this runs after it and blends from
			-- where the menu left the camera, so the return is a move rather than a cut.
			--
			-- Roblox's camera reads camera.CFrame back as its own state next frame, so the blended
			-- frame it rendered is swapped for the pose it computed before it runs again. Left in
			-- place, the blend pulls its zoom in and it snaps back out once the blend stops.
			if self._release then
				local computed: CFrame? = nil
				local function stop()
					RunService:UnbindFromRenderStep(RELEASE_RENDER_STEP_NAME)
					RunService:UnbindFromRenderStep(RELEASE_RESTORE_STEP_NAME)
				end
				stop()
				RunService:BindToRenderStep(RELEASE_RESTORE_STEP_NAME, Enum.RenderPriority.Camera.Value - 1, function()
					if computed then
						self.camera.CFrame = computed
					end
				end)
				RunService:BindToRenderStep(RELEASE_RENDER_STEP_NAME, Enum.RenderPriority.Camera.Value + 1, function()
					local release, eased = self:_releaseProgress()
					if not release then
						stop()
						return
					end
					computed = self.camera.CFrame
					self.camera.CFrame = release.from:Lerp(self.camera.CFrame, eased)
					self.camera.FieldOfView = release.fromFov + (fov - release.fromFov) * eased
				end)
			end
		end
	end
end

function CameraController:clearModifiers()
	self._modifiers = {}
end

function CameraController:setAngles(yaw: number?, pitch: number?)
	if type(yaw) == "number" then
		self._yaw = yaw
	end
	if type(pitch) == "number" then
		self._pitch = math.clamp(pitch, PITCH_MIN, PITCH_MAX)
	end
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
		poseProvider = nil,
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
		if spec.poseProvider ~= nil then
			settings.poseProvider = spec.poseProvider
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

	if self:_applyStagedPose(settings) then
		return
	end

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

	-- Returning from a staged pose: a fixed-time move onto the exact gameplay pose, bypassing the
	-- follow smoothing so the two do not compound into a drift.
	local release, eased = self:_releaseProgress()
	if release then
		self.camera.CFrame = release.from:Lerp(CFrame.lookAt(idealPosition, lookAtPosition), eased)
		self.camera.FieldOfView = release.fromFov + (settings.fov - release.fromFov) * eased
		return
	end

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
	if self.updateLoopBound then
		RunService:UnbindFromRenderStep(CAMERA_RENDER_STEP_NAME)
	end

	RunService:BindToRenderStep(CAMERA_RENDER_STEP_NAME, Enum.RenderPriority.Camera.Value, function()
		if self.mode ~= "OverShoulder" then
			return
		end
		self:_updateCamera()
		CharacterFacingController.getInstance():applyCameraYaw(self._yaw)
	end)
	self.updateLoopBound = true
end

-- Stop the camera update loop
function CameraController:_stopUpdateLoop()
	if self.updateLoopBound then
		RunService:UnbindFromRenderStep(CAMERA_RENDER_STEP_NAME)
	end
	self.updateLoopBound = false
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
	end
	-- In Free mode, do nothing special; panel remains readable via its own placement.
end

-- Clear focus and restore previous OS camera behavior
function CameraController:clearFocus()
	local s: any = self
	s._isFocusing = false
	s._focusTarget = nil
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
