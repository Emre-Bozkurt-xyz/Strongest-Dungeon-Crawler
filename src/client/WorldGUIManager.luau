--!strict
-- World GUI Manager - Handles positioning and management of world-space GUI panels

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local WorldPanelRegistry = require(script.Parent.ui.world.WorldPanelRegistry)
local WorldPanelVisibilityAnimator = require(script.Parent.ui.world.WorldPanelVisibilityAnimator)
local CharacterFacingController = require(script.Parent.CharacterFacingController)
local SharedConfig = require(ReplicatedStorage.Shared.Config)
local DevTuningService = require(script.Parent.dev.DevTuningService)

local WorldGUIManager = {}
WorldGUIManager.__index = WorldGUIManager

type WorldGUIManagerType = {
	player: Player,
	camera: Camera,
	panels: { [string]: PanelConfig },
	updateLoopBound: boolean,
	lastTargetUpdateTime: number,
	cachedTargetPosition: Vector3?,
	cachedTargetRotation: CFrame?,
	smoothCamPart: BasePart?, -- Smooth camera part for buttery movement
	lastAngleBetween: number?, -- Track previous angle to detect direction of change
	currentTween: Tween?, -- Track current movement tween
	_panelGroups: { [string]: { [string]: any } },
	_groupRuntime: { [string]: { [string]: any } },
	_frozenPanels: { [string]: boolean },
	_panelVisOps: { [string]: number },
	_panelVisSeq: number,
	_activeVisTweens: { [Instance]: Tween },
	-- Remove PID controller complexity
	registerPanel: (self: WorldGUIManagerType, config: PanelConfig) -> (),
	unregisterPanel: (self: WorldGUIManagerType, name: string) -> (),
	tweenPanelTo: (self: WorldGUIManagerType, panelName: string, targetCFrame: CFrame, duration: number?) -> Tween?,
	setPanelVisibility: (
		self: WorldGUIManagerType,
		panelName: string,
		visible: boolean,
		duration: number?,
		parent: Instance?
	) -> (),
	destroy: (self: WorldGUIManagerType) -> (),
	_getIdealPanelPosition: (self: WorldGUIManagerType, customOffset: Vector3?) -> Vector3,
	_getIdealPanelRotation: (self: WorldGUIManagerType, panelPosition: Vector3) -> CFrame,
	_updatePanelPosition: (self: WorldGUIManagerType, config: PanelConfig, deltaTime: number) -> (),
	_startUpdateLoop: (self: WorldGUIManagerType) -> (),
	_stopUpdateLoop: (self: WorldGUIManagerType) -> (),
	getPanelTargetPosition: (self: WorldGUIManagerType, panelName: string) -> Vector3?,
	getPanelSnapshot: (self: WorldGUIManagerType, panelName: string) -> PanelSnapshot?,
	getPanelLayoutWidth: (self: WorldGUIManagerType, panelName: string) -> number?,
	updatePanel: (self: WorldGUIManagerType, panelName: string, fields: PanelMutableFields) -> (),
	setPanelFrozen: (self: WorldGUIManagerType, panelName: string, frozen: boolean) -> (),
	setPanelFollowMode: (self: WorldGUIManagerType, panelName: string, mode: "player" | "camera" | "target") -> (),
	_snapPanelToTarget: (self: WorldGUIManagerType, config: PanelConfig) -> (),
	setGroupBasisYaw: (self: WorldGUIManagerType, groupName: string, yaw: number?) -> (),
	getGroupBasisYaw: (self: WorldGUIManagerType, groupName: string) -> number?,
	getGroupParams: (self: WorldGUIManagerType, groupName: string) -> { [string]: any }?,
	setPanelTargetOverrideProvider: (self: WorldGUIManagerType, panelName: string, provider: (() -> Vector3?)?) -> (),
}

local WorldGUIConfig = SharedConfig.WorldGUI
local WORLD_GUI_RENDER_STEP_NAME = "StrongestDungeonCrawler.WorldGUIManager"
-- Camera-relative placement for panels that should follow the camera rather than the player
local CAMERA_PANEL_FORWARD = WorldGUIConfig.cameraPanel.forward
local CAMERA_PANEL_FORWARD_OS = WorldGUIConfig.cameraPanel.forwardOverShoulder
local CAMERA_PANEL_FORWARD_FREE = WorldGUIConfig.cameraPanel.forwardFree
local CAMERA_PANEL_RIGHT = WorldGUIConfig.cameraPanel.right
local CAMERA_PANEL_UP = WorldGUIConfig.cameraPanel.up
local BASE_LERP_SPEED = WorldGUIConfig.defaults.baseLerpSpeed
local UIMenuConfig = SharedConfig.UIMenu

local function num(path: string, fallback: number): number
	local v = DevTuningService.get(path)
	return if type(v) == "number" then v else fallback
end

local function applyWorldGUITuning()
	BASE_LERP_SPEED = num("WorldGUI.defaults.baseLerpSpeed", WorldGUIConfig.defaults.baseLerpSpeed)
	CAMERA_PANEL_FORWARD = num("WorldGUI.cameraPanel.forward", WorldGUIConfig.cameraPanel.forward)
	CAMERA_PANEL_FORWARD_OS = num("WorldGUI.cameraPanel.forwardOverShoulder", WorldGUIConfig.cameraPanel.forwardOverShoulder)
	CAMERA_PANEL_FORWARD_FREE = num("WorldGUI.cameraPanel.forwardFree", WorldGUIConfig.cameraPanel.forwardFree)
	CAMERA_PANEL_RIGHT = num("WorldGUI.cameraPanel.right", WorldGUIConfig.cameraPanel.right)
	CAMERA_PANEL_UP = num("WorldGUI.cameraPanel.up", WorldGUIConfig.cameraPanel.up)
end

applyWorldGUITuning()
DevTuningService.subscribe("WorldGUI", function()
	applyWorldGUITuning()
end)

-- Track active tweens per instance to avoid overlapping animations
local function playTweenReplace(self: WorldGUIManagerType, inst: Instance, info: TweenInfo, props: { [string]: any })
	local tweenMap = (self :: any)._activeVisTweens :: { [Instance]: Tween }
	local existing = tweenMap[inst]
	if existing then
		pcall(function()
			existing:Cancel()
		end)
	end
	return WorldPanelVisibilityAnimator.playReplace(tweenMap, inst, info, props)
end

type PanelConfig = {
	name: string,
	part: BasePart,
	group: string?, -- Optional panel group (shared params)
	offset: Vector3?, -- Optional custom offset from default position
	camSpaceOffset: Vector3?, -- Optional camera-space offset (X=right, Y=up, Z=forward)
	playerSpaceOffset: Vector3?, -- Optional player-space offset (X=right, Y=up, Z=forward)
	_basePlayerSpaceOffset: Vector3?, -- Internal: authored/tuned player-space offset
	playerOffsetMode: "full" | "yaw"?, -- Optional: use yaw-only axes for playerSpaceOffset
	faceCamera: boolean?, -- Whether panel should face the camera (default true)
	faceMode: "camera" | "player" | "playerYaw" | "target"?, -- Optional facing behavior (default "camera")
	faceBlend: number?, -- Optional 0..1 blend toward camera yaw when using playerYaw
	followMode: "player" | "camera" | "target"?, -- New: explicit follow mode (default "player"). 'target' follows a provided BasePart
	followTarget: BasePart?, -- When followMode is 'target', this part is used as the anchor
	followModeLock: boolean?, -- When true, external callers should not override followMode
	minRadius: number?, -- Optional minimum distance to anchor
	maxRadius: number?, -- Optional maximum distance to anchor
	radiusPadding: number?, -- Optional extra min-radius padding (e.g. panel depth/2)
	lerpSpeed: number?, -- Optional per-panel lerp speed (defaults to BASE_LERP_SPEED)
	visible: boolean?, -- Current visibility state
	targetOverrideProvider: (() -> Vector3?)?,
}

type PanelMutableFields = {
	group: string?,
	offset: Vector3?,
	camSpaceOffset: Vector3?,
	playerSpaceOffset: Vector3?,
	playerOffsetMode: "full" | "yaw"?,
	faceMode: "camera" | "player" | "playerYaw" | "target"?,
	faceBlend: number?,
	followMode: "player" | "camera" | "target"?,
	followTarget: BasePart?,
	followModeLock: boolean?,
	minRadius: number?,
	maxRadius: number?,
	radiusPadding: number?,
	lerpSpeed: number?,
	targetOverrideProvider: (() -> Vector3?)?,
}

type PanelSnapshot = {
	name: string,
	part: BasePart,
	group: string?,
	offset: Vector3,
	camSpaceOffset: Vector3,
	playerSpaceOffset: Vector3,
	basePlayerSpaceOffset: Vector3,
	playerOffsetMode: "full" | "yaw"?,
	faceMode: "camera" | "player" | "playerYaw" | "target"?,
	faceBlend: number?,
	followMode: "player" | "camera" | "target"?,
	followTarget: BasePart?,
	followModeLock: boolean?,
	minRadius: number?,
	maxRadius: number?,
	radiusPadding: number?,
	lerpSpeed: number?,
	visible: boolean,
}

local WorldGUIManager_Instance = nil

local function getEffectivePlayerSpaceOffset(config: PanelConfig): Vector3
	local base = (config :: any)._basePlayerSpaceOffset
	if typeof(base) ~= "Vector3" then
		base = (config :: any).playerSpaceOffset or Vector3.new(0, 0, 0)
	end
	return base :: Vector3
end

local function getPanelLayoutWidthFromConfig(config: PanelConfig): number
	local layoutWidth = config.part:GetAttribute("LayoutWidth")
	if type(layoutWidth) == "number" and layoutWidth > 0 then
		return layoutWidth
	end
	return math.max(config.part.Size.X, config.part.Size.Z)
end

local function buildPanelSnapshot(config: PanelConfig): PanelSnapshot
	return {
		name = config.name,
		part = config.part,
		group = config.group,
		offset = config.offset or Vector3.zero,
		camSpaceOffset = config.camSpaceOffset or Vector3.zero,
		playerSpaceOffset = config.playerSpaceOffset or Vector3.zero,
		basePlayerSpaceOffset = getEffectivePlayerSpaceOffset(config),
		playerOffsetMode = config.playerOffsetMode,
		faceMode = config.faceMode,
		faceBlend = config.faceBlend,
		followMode = config.followMode,
		followTarget = config.followTarget,
		followModeLock = config.followModeLock,
		minRadius = config.minRadius,
		maxRadius = config.maxRadius,
		radiusPadding = config.radiusPadding,
		lerpSpeed = config.lerpSpeed,
		visible = config.visible == true,
	}
end

local function clampRadius(anchor: Vector3, desired: Vector3, minRadius: number?, maxRadius: number?): Vector3
	if minRadius == nil and maxRadius == nil then
		return desired
	end
	local offset = desired - anchor
	local dist = offset.Magnitude
	if dist <= 1e-4 then
		return desired
	end
	local targetDist = dist
	if type(minRadius) == "number" and dist < minRadius then
		targetDist = minRadius
	end
	if type(maxRadius) == "number" and dist > maxRadius then
		targetDist = maxRadius
	end
	if targetDist ~= dist then
		return anchor + offset.Unit * targetDist
	end
	return desired
end

local function computeYawAxes(root: BasePart): (Vector3, Vector3, Vector3)
	local forward = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if forward.Magnitude <= 1e-4 then
		forward = Vector3.new(0, 0, -1)
	else
		forward = forward.Unit
	end
	local up = Vector3.yAxis
	local right = forward:Cross(up)
	if right.Magnitude <= 1e-4 then
		right = Vector3.new(1, 0, 0)
	else
		right = right.Unit
	end
	return right, up, forward
end

local function computeYawAxesFromYaw(yaw: number): (Vector3, Vector3, Vector3)
	local forward = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
	if forward.Magnitude <= 1e-4 then
		forward = Vector3.new(0, 0, -1)
	else
		forward = forward.Unit
	end
	local up = Vector3.yAxis
	local right = forward:Cross(up)
	if right.Magnitude <= 1e-4 then
		right = Vector3.new(1, 0, 0)
	else
		right = right.Unit
	end
	return right, up, forward
end

local function getMenuGroupName(): string
	local tuned = DevTuningService.get("UIMenu.groupName")
	if type(tuned) == "string" and tuned ~= "" then
		return tuned
	end
	return UIMenuConfig.groupName
end

local function shouldUseGroupBasis(groupName: string?, offsetMode: string?): boolean
	return groupName == getMenuGroupName() and offsetMode == "yaw"
end

local function resolveOffsetAxes(self: WorldGUIManagerType, groupName: string?, root: BasePart, offsetMode: string?): (Vector3, Vector3, Vector3)
	if shouldUseGroupBasis(groupName, offsetMode) then
		local runtime = (self :: any)._groupRuntime
		local groupRuntime = runtime and runtime[groupName or ""]
		local basisYaw = groupRuntime and groupRuntime.basisYaw
		if type(basisYaw) == "number" then
			return computeYawAxesFromYaw(basisYaw)
		end
	end
	if offsetMode == "yaw" then
		return computeYawAxes(root)
	end
	return root.CFrame.RightVector, root.CFrame.UpVector, root.CFrame.LookVector
end

local function getRadiusLimits(self: WorldGUIManagerType, config: PanelConfig): (number?, number?)
	local group = config.group and self._panelGroups[config.group] or nil
	local padding = (config :: any).radiusPadding or (group and group.radiusPadding) or 0
	local minRadius = (config :: any).minRadius or (group and group.minRadius) or nil
	if type(minRadius) == "number" then
		minRadius = minRadius + padding
	end
	local maxRadius = (config :: any).maxRadius or (group and group.maxRadius) or nil
	return minRadius, maxRadius
end

local function smoothTowardTarget(current: CFrame, target: CFrame, deltaTime: number, speed: number): CFrame
	local alpha = 1 - math.exp(-math.max(0.1, speed) * math.max(0, deltaTime))
	return current:Lerp(target, alpha)
end

local function resolvePanelTargetPosition(self: WorldGUIManagerType, config: PanelConfig): Vector3?
	if not config.part or not config.name then
		return nil
	end

	local overrideProvider = (config :: any).targetOverrideProvider
	if overrideProvider ~= nil then
		local ok, overridePosition = pcall(overrideProvider)
		if ok and typeof(overridePosition) == "Vector3" then
			return overridePosition
		end
	end

	local mode = (config.followMode or "player") :: any
	if mode == "target" then
		local tgt = config.followTarget
		if not tgt or not tgt.Parent then
			return nil
		end

		local desired = tgt.Position + (config.offset or Vector3.new(0, 0, 0))
		local pso = getEffectivePlayerSpaceOffset(config)
		if pso.X ~= 0 or pso.Y ~= 0 or pso.Z ~= 0 then
			local group = config.group and self._panelGroups[config.group] or nil
			local offsetMode = (config :: any).playerOffsetMode or (group and group.playerOffsetMode)
			local r, u, f = resolveOffsetAxes(self, config.group, tgt, offsetMode)
			desired += r * pso.X + u * pso.Y + f * pso.Z
		end

		local minRadius, maxRadius = getRadiusLimits(self, config)
		return clampRadius(tgt.Position, desired, minRadius, maxRadius)
	end

	if mode == "camera" then
		local cam = self.camera
		if not cam then
			return nil
		end

		local camCF = cam.CFrame
		local right = camCF.RightVector
		local up = camCF.UpVector
		local look = camCF.LookVector
		local basePos = camCF.Position
		local forwardDist = CAMERA_PANEL_FORWARD
		if config.name == "SystemPanel" then
			if cam.CameraType == Enum.CameraType.Scriptable then
				forwardDist = CAMERA_PANEL_FORWARD_OS
			else
				forwardDist = CAMERA_PANEL_FORWARD_FREE
			end
		end

		local desired = basePos + right * CAMERA_PANEL_RIGHT + up * CAMERA_PANEL_UP + look * forwardDist
		desired += config.offset or Vector3.new(0, 0, 0)

		local cso = config.camSpaceOffset or Vector3.new(0, 0, 0)
		if cso.X ~= 0 or cso.Y ~= 0 or cso.Z ~= 0 then
			desired += right * cso.X + up * cso.Y + look * cso.Z
		end

		local minRadius, maxRadius = getRadiusLimits(self, config)
		desired = clampRadius(basePos, desired, minRadius, maxRadius)

		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local exclude = {}
		if self.player.Character then
			table.insert(exclude, self.player.Character)
		end
		table.insert(exclude, config.part)
		params.FilterDescendantsInstances = (exclude :: any) :: { Instance }
		local toDesired = desired - basePos
		local dist = toDesired.Magnitude
		if dist > 0 then
			local hit = Workspace:Raycast(basePos, toDesired, params)
			if hit then
				local safe = math.max(hit.Distance - 0.5, 2.75)
				desired = basePos + toDesired.Unit * safe
			end
		end

		return clampRadius(basePos, desired, minRadius, maxRadius)
	end

	if not self.player.Character then
		return nil
	end
	local playerRootPart = self.player.Character:FindFirstChild("HumanoidRootPart")
	if not playerRootPart or not playerRootPart:IsA("BasePart") then
		return nil
	end

	local root = playerRootPart
	local playerPosition = root.Position
	local targetPosition = playerPosition + (config.offset or Vector3.new(0, 0, 0))
	local pso = getEffectivePlayerSpaceOffset(config)
	if pso.X ~= 0 or pso.Y ~= 0 or pso.Z ~= 0 then
		local group = config.group and self._panelGroups[config.group] or nil
		local offsetMode = (config :: any).playerOffsetMode or (group and group.playerOffsetMode)
		local r, u, f = resolveOffsetAxes(self, config.group, root, offsetMode)
		local overrideForward = CharacterFacingController.getInstance():getPresentationBasisForward(root)
		if overrideForward and overrideForward.Magnitude > 1e-4 then
			f = overrideForward.Unit
			u = Vector3.yAxis
			r = f:Cross(u)
		end
		targetPosition += r * pso.X + u * pso.Y + f * pso.Z
	end

	local minRadius, maxRadius = getRadiusLimits(self, config)
	return clampRadius(playerPosition, targetPosition, minRadius, maxRadius)
end

local function resolvePanelTargetCFrame(self: WorldGUIManagerType, config: PanelConfig): CFrame?
	local targetPosition = resolvePanelTargetPosition(self, config)
	if not targetPosition then
		return nil
	end
	return self:_getIdealPanelRotation(config, targetPosition)
end

function WorldGUIManager.new()
	if WorldGUIManager_Instance then
		return WorldGUIManager_Instance
	end

	local self = setmetatable({}, WorldGUIManager)
	WorldGUIManager_Instance = self

	local registry = WorldPanelRegistry.new()
	self.player = Players.LocalPlayer
	self.camera = Workspace.CurrentCamera
	self.panels = registry.panels :: { [string]: PanelConfig }
	self._panelGroups = registry.groups :: { [string]: { [string]: any } }
	self._groupRuntime = {} :: { [string]: { [string]: any } }
	self._frozenPanels = registry.frozen :: { [string]: boolean }
	self._panelVisOps = registry.visibilityOps :: { [string]: number }
	self._panelVisSeq = registry.visibilitySeq :: number
	self._activeVisTweens = registry.activeTweens :: { [Instance]: Tween }
	self.updateLoopBound = false

	self:_startUpdateLoop()

	return self
end

-- Register a world-space panel for management
function WorldGUIManager:registerPanel(config: PanelConfig)
	if not config.part or not config.name then
		warn("WorldGUIManager: Invalid panel config - missing part or name")
		return
	end

	-- Set defaults
	config.faceCamera = config.faceCamera ~= false -- Default true
	-- Default followMode to player when not provided
	config.followMode = config.followMode or "player"
	config.offset = config.offset or Vector3.new(0, 0, 0)
	config.camSpaceOffset = config.camSpaceOffset or Vector3.new(0, 0, 0)
	local cfgAny = config :: any
	cfgAny.playerSpaceOffset = cfgAny.playerSpaceOffset or Vector3.new(0, 0, 0)
	config._basePlayerSpaceOffset = cfgAny.playerSpaceOffset
	config.visible = false

	self.panels[config.name] = config

	-- Initial positioning (use 1/60 as default deltaTime for initial setup)
	self:_updatePanelPosition(config, 1 / 60)
	
	-- print(`🌐 WorldGUIManager: Registered panel '{config.name}'`)
end

-- Unregister a panel
function WorldGUIManager:unregisterPanel(name: string)
	if self.panels[name] then
		self.panels[name] = nil
		-- print(`🌐 WorldGUIManager: Unregistered panel '{name}'`)
	end
end

-- Get the ideal rotation for a panel to face the camera
function WorldGUIManager:_getIdealPanelRotation(config: PanelConfig, panelPosition: Vector3): CFrame
	if config.faceCamera == false then
		return CFrame.new(panelPosition)
	end

	local mode = config.faceMode or "camera"
	if mode == "player" then
		local char = self.player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			return CFrame.lookAt(panelPosition, hrp.Position, Vector3.new(0, 1, 0))
		end
	elseif mode == "playerYaw" then
		local char = self.player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			local toPlayer = hrp.Position - panelPosition
			local flat = Vector3.new(toPlayer.X, 0, toPlayer.Z)
			if flat.Magnitude > 1e-4 then
				local faceVec = flat.Unit
				local blend = config.faceBlend
				if type(blend) == "number" and blend > 0 then
					local camPos = self.camera and self.camera.CFrame.Position or (panelPosition + faceVec)
					local camToPanel = camPos - panelPosition
					local camFlat = Vector3.new(camToPanel.X, 0, camToPanel.Z)
					if camFlat.Magnitude > 1e-4 then
						faceVec = faceVec:Lerp(camFlat.Unit, math.clamp(blend, 0, 1)).Unit
					end
				end
				return CFrame.lookAt(panelPosition, panelPosition + faceVec, Vector3.new(0, 1, 0))
			end
		end
	elseif mode == "target" then
		local tgt = config.followTarget
		if tgt and tgt.Parent then
			return CFrame.lookAt(panelPosition, tgt.Position, Vector3.new(0, 1, 0))
		end
	end
	local cameraPosition = self.camera.CFrame.Position :: Vector3

	-- Make panel face the camera - use lookAt properly
	return CFrame.lookAt(panelPosition, cameraPosition, Vector3.new(0, 1, 0))
end

-- Update a single panel's position and rotation
function WorldGUIManager:_updatePanelPosition(config: PanelConfig, deltaTime: number)
	if not config.part or not config.name then
		warn(`WorldGUIManager: Panel '{config.name}' is missing part or name`)
		return
	end

	local targetCF = resolvePanelTargetCFrame(self, config)
	if not targetCF then
		return
	end

	local group = config.group and self._panelGroups[config.group] or nil
	local speed = (config :: any).lerpSpeed or (group and group.lerpSpeed) or BASE_LERP_SPEED
	config.part.CFrame = smoothTowardTarget(config.part.CFrame, targetCF, deltaTime, speed)
end

function WorldGUIManager:_snapPanelToTarget(config: PanelConfig)
	if not config.part or not config.name then
		return
	end

	local targetCF = resolvePanelTargetCFrame(self, config)
	if not targetCF then
		return
	end

	config.part.CFrame = targetCF
end

function WorldGUIManager:setPanelFollowTarget(panelName: string, followTarget: BasePart?)
	local cfg = self.panels[panelName]
	if not cfg then return end
	local cfgAny = cfg :: any
	cfgAny.followTarget = followTarget
end

-- Adjust a panel's lerp speed at runtime
function WorldGUIManager:setPanelLerpSpeed(panelName: string, speed: number)
	local cfg = self.panels[panelName]
	if not cfg then return end
	if type(speed) ~= "number" then return end
	local cfgAny = cfg :: any
	cfgAny.lerpSpeed = speed
end

-- Main update loop
function WorldGUIManager:_startUpdateLoop()
	if self.updateLoopBound then
		RunService:UnbindFromRenderStep(WORLD_GUI_RENDER_STEP_NAME)
	end

	-- Update after the custom camera step so panel solve always sees the latest
	-- camera CFrame and character yaw for this rendered frame.
	RunService:BindToRenderStep(WORLD_GUI_RENDER_STEP_NAME, Enum.RenderPriority.Camera.Value + 1, function(deltaTime: number)
		for _, config in pairs(self.panels) do
			if not self._frozenPanels[config.name] then
				self:_updatePanelPosition(config, deltaTime)
			end
		end
	end)
	self.updateLoopBound = true
end

function WorldGUIManager:_stopUpdateLoop()
	if self.updateLoopBound then
		RunService:UnbindFromRenderStep(WORLD_GUI_RENDER_STEP_NAME)
	end
	self.updateLoopBound = false
end

-- Tween a panel to a specific position (useful for animations)
function WorldGUIManager:tweenPanelTo(panelName: string, targetCFrame: CFrame, duration: number?)
	local config = self.panels[panelName]
	if not config or not config.part then
		warn(`WorldGUIManager: Panel '{panelName}' not found`)
		return
	end

	duration = duration or 1

	local tween = TweenService:Create(
		config.part,
		TweenInfo.new(duration, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ CFrame = targetCFrame }
	)

	tween:Play()
	return tween
end

-- Show/hide a panel with smooth animation
function WorldGUIManager:setPanelVisibility(panelName: string, visible: boolean, duration: number?, parent: Instance?)
	local config = self.panels[panelName]
	if not config or not config.part then
		warn(`WorldGUIManager: Panel '{panelName}' not found`)
		return
	end

	duration = duration or 0.3

	-- Establish an operation token to identify delayed actions belonging to this call
	self._panelVisSeq += 1
	local opId = self._panelVisSeq
	self._panelVisOps[panelName] = opId

	-- Parent on show immediately so the panel is present during fade-in; default to Workspace
	if visible then
		local targetParent: Instance = parent or Workspace
		local partForParent: any = config.part
		partForParent.Parent = targetParent
	end

	-- Function to handle parts with original transparency
	local function tweenPartTransparency(part: BasePart)
		-- Store original transparency if not already stored
		if part:GetAttribute("OriginalTransparency") == nil then
			part:SetAttribute("OriginalTransparency", part.Transparency)
		end

		local originalTransparency = part:GetAttribute("OriginalTransparency") or 0
		local targetTransparency = visible and originalTransparency or 1

		playTweenReplace(self, part, TweenInfo.new(duration, Enum.EasingStyle.Quart), { Transparency = targetTransparency })
	end

	-- Tween all GUI descendants: background, text, image, and strokes; also handle borders
	local function tweenGuiTransparency(instance: Instance)
		if instance:IsA("SurfaceGui") or instance:IsA("BillboardGui") then
			for _, child in ipairs(instance:GetDescendants()) do
				if child:IsA("GuiObject") then
					-- Background
					if child:GetAttribute("OriginalBackgroundTransparency") == nil then
						child:SetAttribute("OriginalBackgroundTransparency", child.BackgroundTransparency)
					end
					local origBg = child:GetAttribute("OriginalBackgroundTransparency") or 0
					local targetBg = visible and origBg or 1
					local props: any = { BackgroundTransparency = targetBg }

					-- Text
					if child:IsA("TextLabel") or child:IsA("TextButton") or child:IsA("TextBox") then
						if child:GetAttribute("OriginalTextTransparency") == nil then
							child:SetAttribute("OriginalTextTransparency", child.TextTransparency)
						end
						if child:GetAttribute("OriginalTextStrokeTransparency") == nil then
							child:SetAttribute("OriginalTextStrokeTransparency", child.TextStrokeTransparency)
						end
						local oTxt = child:GetAttribute("OriginalTextTransparency") or 0
						local oStroke = child:GetAttribute("OriginalTextStrokeTransparency") or 1
						props.TextTransparency = visible and oTxt or 1
						props.TextStrokeTransparency = visible and oStroke or 1
					end

					-- Image
					if child:IsA("ImageLabel") or child:IsA("ImageButton") then
						if child:GetAttribute("OriginalImageTransparency") == nil then
							child:SetAttribute("OriginalImageTransparency", child.ImageTransparency)
						end
						local oImg = child:GetAttribute("OriginalImageTransparency") or 0
						props.ImageTransparency = visible and oImg or 1
					end

					-- Apply tween to the GuiObject
					playTweenReplace(self, child, TweenInfo.new(duration, Enum.EasingStyle.Quart), props)

					-- UIStroke borders attached to this GuiObject
					for _, deco in ipairs(child:GetChildren()) do
						if deco:IsA("UIStroke") then
							if deco:GetAttribute("OriginalStrokeTransparency") == nil then
								deco:SetAttribute("OriginalStrokeTransparency", deco.Transparency)
							end
							local oSt = deco:GetAttribute("OriginalStrokeTransparency") or 0
							local tSt = visible and oSt or 1
							playTweenReplace(self,
								deco,
								TweenInfo.new(duration, Enum.EasingStyle.Quart),
								{ Transparency = tSt }
							)
						end
					end

					-- Legacy Frame border handling (BorderSizePixel); not tweenable so toggle at edges
					if
						child:IsA("Frame")
						or child:IsA("TextLabel")
						or child:IsA("TextButton")
						or child:IsA("TextBox")
						or child:IsA("ImageLabel")
						or child:IsA("ImageButton")
					then
						if (child :: any).BorderSizePixel ~= nil then
							local frame = child :: any
							if frame:GetAttribute("OriginalBorderSizePixel") == nil then
								frame:SetAttribute("OriginalBorderSizePixel", frame.BorderSizePixel)
							end
							local originalBorder = frame:GetAttribute("OriginalBorderSizePixel")
								or frame.BorderSizePixel
							if visible then
								frame.BorderSizePixel = originalBorder
							else
								task.delay(duration, function()
									-- hide border after fade completes (only if this op is still current and still hidden)
									if self._panelVisOps[panelName] == opId and not (config.visible :: any) then
										if frame and frame.Parent then
											frame.BorderSizePixel = 0
										end
									end
								end)
							end
						end
					end
				end
			end
		end
	end

	-- Tween the main part if it's a BasePart
	local partAny: any = config.part
	if partAny:IsA("BasePart") then
		tweenPartTransparency(partAny)
	end

	-- Tween all child parts with their original transparency
	for _, child in ipairs(config.part:GetDescendants()) do
		if child:IsA("BasePart") then
			tweenPartTransparency(child)
		end
		tweenGuiTransparency(child)
	end

	-- Record intended visibility immediately (last write wins)
	config.visible = visible

	-- On hide, unparent after fade completes if this op is still the latest
	if not visible then
		task.delay(duration, function()
			if self._panelVisOps[panelName] == opId and not (config.visible :: any) then
				if config.part and (config.part :: any).Parent then
					local partAny = config.part :: any
					partAny.Parent = nil
				end
			end
		end)
	end
end

-- Reset the initial panel position (useful when respawning or repositioning)
function WorldGUIManager:resetInitialDirection()
	self.idealPanelPosition = nil
end

-- Get the GUI panel position for camera targeting
function WorldGUIManager:getPanelTargetPosition(panelName: string): Vector3?
	local config = self.panels[panelName]
	if not config or not config.part then
		return nil
	end
	return resolvePanelTargetPosition(self, config)
end

function WorldGUIManager:getPanelSnapshot(panelName: string): PanelSnapshot?
	local config = self.panels[panelName]
	if not config or not config.part then
		return nil
	end
	return buildPanelSnapshot(config)
end

function WorldGUIManager:getPanelLayoutWidth(panelName: string): number?
	local config = self.panels[panelName]
	if not config or not config.part then
		return nil
	end
	return getPanelLayoutWidthFromConfig(config)
end

function WorldGUIManager:updatePanel(panelName: string, fields: PanelMutableFields)
	local cfg = self.panels[panelName]
	if not cfg or not fields then
		return
	end

	if fields.group ~= nil then
		cfg.group = fields.group
	end
	if fields.offset ~= nil then
		cfg.offset = fields.offset
	end
	if fields.camSpaceOffset ~= nil then
		cfg.camSpaceOffset = fields.camSpaceOffset
	end
	if fields.playerSpaceOffset ~= nil then
		cfg.playerSpaceOffset = fields.playerSpaceOffset
		cfg._basePlayerSpaceOffset = fields.playerSpaceOffset
	end
	if fields.playerOffsetMode ~= nil then
		cfg.playerOffsetMode = fields.playerOffsetMode
	end
	if fields.faceMode ~= nil then
		cfg.faceMode = fields.faceMode
	end
	if fields.faceBlend ~= nil then
		cfg.faceBlend = fields.faceBlend
	end
	if fields.followMode ~= nil then
		cfg.followMode = fields.followMode
	end
	if fields.followTarget ~= nil or fields.followMode == "target" then
		cfg.followTarget = fields.followTarget
	end
	if fields.followModeLock ~= nil then
		cfg.followModeLock = fields.followModeLock
	end
	if fields.minRadius ~= nil then
		cfg.minRadius = fields.minRadius
	end
	if fields.maxRadius ~= nil then
		cfg.maxRadius = fields.maxRadius
	end
	if fields.radiusPadding ~= nil then
		cfg.radiusPadding = fields.radiusPadding
	end
	if fields.lerpSpeed ~= nil then
		cfg.lerpSpeed = fields.lerpSpeed
	end
	if fields.targetOverrideProvider ~= nil then
		cfg.targetOverrideProvider = fields.targetOverrideProvider
	end
end

function WorldGUIManager:getGroupParams(groupName: string): { [string]: any }?
	if type(groupName) ~= "string" or groupName == "" then
		return nil
	end
	return self._panelGroups[groupName]
end

-- Expose all registered panel parts for systems that need to ignore them (e.g., camera collision raycasts)
function WorldGUIManager:getPanelParts(): { Instance }
	local parts: { Instance } = {}
	for _, cfg in pairs(self.panels) do
		if cfg and cfg.part then
			table.insert(parts, cfg.part)
		end
	end
	return parts
end

function WorldGUIManager:setPanelFrozen(panelName: string, frozen: boolean)
	if frozen then
		self._frozenPanels[panelName] = true
	else
		self._frozenPanels[panelName] = nil :: any
	end
end

function WorldGUIManager:setPanelFollowMode(panelName: string, mode: "player" | "camera" | "target")
	local cfg = self.panels[panelName]
	if not cfg then
		return
	end
	if (cfg :: any).followModeLock then
		return
	end
	local anyCfg: any = cfg
	anyCfg.followMode = mode
	-- Snap immediately to new target to avoid residual offsets
	self:_snapPanelToTarget(cfg)
end

function WorldGUIManager:setPanelFollowModeLock(panelName: string, locked: boolean)
	local cfg = self.panels[panelName]
	if not cfg then
		return
	end
	local cfgAny = cfg :: any
	cfgAny.followModeLock = locked and true or false
end

function WorldGUIManager:setPanelGroup(panelName: string, groupName: string?)
	local cfg = self.panels[panelName]
	if not cfg then
		return
	end
	local cfgAny = cfg :: any
	cfgAny.group = groupName
end

function WorldGUIManager:setGroupParams(groupName: string, params: { [string]: any })
	if type(groupName) ~= "string" or groupName == "" then
		return
	end
	self._panelGroups[groupName] = self._panelGroups[groupName] or {}
	for key, value in pairs(params) do
		self._panelGroups[groupName][key] = value
	end
end

function WorldGUIManager:setGroupBasisYaw(groupName: string, yaw: number?)
	if type(groupName) ~= "string" or groupName == "" then
		return
	end
	self._groupRuntime[groupName] = self._groupRuntime[groupName] or {}
	if type(yaw) == "number" then
		self._groupRuntime[groupName].basisYaw = yaw
	else
		self._groupRuntime[groupName].basisYaw = nil
	end
end

function WorldGUIManager:getGroupBasisYaw(groupName: string): number?
	if type(groupName) ~= "string" or groupName == "" then
		return nil
	end
	local runtime = self._groupRuntime[groupName]
	local yaw = runtime and runtime.basisYaw
	return if type(yaw) == "number" then yaw else nil
end

function WorldGUIManager:setPanelTargetOverrideProvider(panelName: string, provider: (() -> Vector3?)?)
	local cfg = self.panels[panelName]
	if not cfg then
		return
	end
	local cfgAny = cfg :: any
	cfgAny.targetOverrideProvider = provider
end

function WorldGUIManager:setPanelCameraSpaceOffset(panelName: string, off: Vector3)
	local cfg = self.panels[panelName]
	if not cfg then
		return
	end
	local cfgAny = cfg :: any
	cfgAny.camSpaceOffset = off
end

function WorldGUIManager:setPanelPlayerSpaceOffset(panelName: string, off: Vector3)
	local cfg = self.panels[panelName]
	if not cfg then
		return
	end
	local cfgAny = cfg :: any
	-- Base offset is authored/tuned per panel; layout contributes a separate delta.
	cfgAny.playerSpaceOffset = off
	cfgAny._basePlayerSpaceOffset = off
end

function WorldGUIManager:isPanelVisible(panelName: string): boolean
	local config = self.panels[panelName]
	if not config or not config.part then
		warn(`WorldGUIManager: Panel '{panelName}' not found`)
		return false
	end

	return config.visible
end

-- Cleanup
function WorldGUIManager:destroy()
	self:_stopUpdateLoop()
	local selfAny = self :: any

	-- Clean up current tween
	if self.currentTween then
		self.currentTween:Cancel()
	end
	selfAny.currentTween = nil

	-- Clean up smooth cam part
	if self.smoothCamPart then
		self.smoothCamPart:Destroy()
	end
	selfAny.smoothCamPart = nil

	self.panels = {}
	self._panelGroups = {}
	self._groupRuntime = {}
	self._frozenPanels = {}
	self._panelVisOps = {}
	self._panelVisSeq = 0
	self._activeVisTweens = {}
	WorldGUIManager_Instance = nil :: any
end

-- Get the singleton instance
function WorldGUIManager.getInstance()
	return WorldGUIManager_Instance or WorldGUIManager.new()
end

function WorldGUIManager.peekInstance()
	return WorldGUIManager_Instance
end

return WorldGUIManager
