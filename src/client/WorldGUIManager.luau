--!strict
-- World GUI Manager - Handles positioning and management of world-space GUI panels

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local WorldGUIManager = {}
WorldGUIManager.__index = WorldGUIManager

type WorldGUIManagerType = {
	player: Player,
	camera: Camera,
	panels: { [string]: PanelConfig },
	heartbeatConnection: RBXScriptConnection?,
	lastTargetUpdateTime: number,
	cachedTargetPosition: Vector3?,
	cachedTargetRotation: CFrame?,
	smoothCamPart: BasePart?, -- Smooth camera part for buttery movement
	lastAngleBetween: number?, -- Track previous angle to detect direction of change
	currentTween: Tween?, -- Track current movement tween
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
	getGUIPosition: (self: WorldGUIManagerType) -> Vector3,
	setPanelFrozen: (self: WorldGUIManagerType, panelName: string, frozen: boolean) -> (),
	setPanelFollowMode: (self: WorldGUIManagerType, panelName: string, mode: "player" | "camera") -> (),
	_snapPanelToTarget: (self: WorldGUIManagerType, config: PanelConfig) -> (),
}

-- Configuration
local GUI_OFFSET = Vector3.new(0, 1.5, -3.5)
-- Camera-relative placement for panels that should follow the camera rather than the player
local CAMERA_PANEL_FORWARD = 4.0 -- default studs in front of camera (non-SystemPanel or legacy)
local CAMERA_PANEL_FORWARD_OS = 3.5 -- Over-Shoulder (Scriptable) ideal distance for SystemPanel
local CAMERA_PANEL_FORWARD_FREE = 3.5 -- Free camera (Custom) ideal distance for SystemPanel
local CAMERA_PANEL_RIGHT = 0.0 -- shift to the right (positive) or left (negative)
local CAMERA_PANEL_UP = -0.5 -- slight downward offset to better frame content
local BASE_LERP_SPEED = 8.0 -- Base lerp speed

-- Track active tweens per instance to avoid overlapping animations
local activeVisTweens: { [Instance]: Tween } = {}
local function playTweenReplace(inst: Instance, info: TweenInfo, props: { [string]: any })
	local existing = activeVisTweens[inst]
	if existing then
		pcall(function()
			existing:Cancel()
		end)
	end
	local tween = TweenService:Create(inst, info, props)
	activeVisTweens[inst] = tween
	tween.Completed:Connect(function()
		-- Only clear if this tween is still the current one
		if activeVisTweens[inst] == tween then
			activeVisTweens[inst] = nil
		end
	end)
	tween:Play()
	return tween
end

-- Track latest visibility operation per panel to guard delayed actions
local panelVisOps: { [string]: number } = {}
local panelVisSeq = 0

type PanelConfig = {
	name: string,
	part: BasePart,
	offset: Vector3?, -- Optional custom offset from default position
	camSpaceOffset: Vector3?, -- Optional camera-space offset (X=right, Y=up, Z=forward)
	playerSpaceOffset: Vector3?, -- Optional player-space offset (X=right, Y=up, Z=forward)
	faceCamera: boolean?, -- Whether panel should face the camera (default true)
	followMode: "player" | "camera" | "target"?, -- New: explicit follow mode (default "player"). 'target' follows a provided BasePart
	followTarget: BasePart?, -- When followMode is 'target', this part is used as the anchor
	lerpSpeed: number?, -- Optional per-panel lerp speed (defaults to BASE_LERP_SPEED)
	visible: boolean?, -- Current visibility state
}

local WorldGUIManager_Instance = nil
local frozenPanels: { [string]: boolean } = {}

function WorldGUIManager.new()
	if WorldGUIManager_Instance then
		return WorldGUIManager_Instance
	end

	local self = setmetatable({}, WorldGUIManager)
	WorldGUIManager_Instance = self

	self.player = Players.LocalPlayer
	self.camera = Workspace.CurrentCamera
	self.panels = {} :: { [string]: PanelConfig }
	self.heartbeatConnection = nil :: RBXScriptConnection?

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
	-- Default per-panel lerp speed
	(config :: any).lerpSpeed = (config :: any).lerpSpeed or BASE_LERP_SPEED
	config.offset = config.offset or Vector3.new(0, 0, 0)
	config.camSpaceOffset = config.camSpaceOffset or Vector3.new(0, 0, 0)
	local cfgAny = config :: any
	cfgAny.playerSpaceOffset = cfgAny.playerSpaceOffset or Vector3.new(0, 0, 0)
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
function WorldGUIManager:_getIdealPanelRotation(panelPosition: Vector3): CFrame
	local cameraPosition = self.camera.CFrame.Position :: Vector3

	-- Make panel face the camera - use lookAt properly
	return CFrame.lookAt(panelPosition, cameraPosition, Vector3.new(0, 1, 0))
end

-- Compute an ideal world position for the camera to reference/aim at
function WorldGUIManager:_getIdealPanelPosition(customOffset: Vector3?): Vector3
	local offset = customOffset or Vector3.new(0, 0, 0)

	-- Prefer an explicitly visible panel (e.g., SystemPanel)
	local systemCfg: any = self.panels["SystemPanel"]
	if systemCfg and systemCfg.part and (systemCfg.visible or true) then
		local p: any = systemCfg.part
		return p.Position + offset
	end

	-- Otherwise, use the first visible panel; if none marked visible, just take the first registered
	for _, cfgAny in pairs(self.panels) do
		local cfg: any = cfgAny
		if cfg.part and cfg.visible then
			local p: any = cfg.part
			return p.Position + offset
		end
	end
	for _, cfgAny in pairs(self.panels) do
		local cfg: any = cfgAny
		if cfg.part then
			local p: any = cfg.part
			return p.Position + offset
		end
	end

	-- Fallback: head-level in front of the player
	if self.player.Character then
		local hrp = self.player.Character:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			local h: any = hrp
			return h.Position + Vector3.new(0, GUI_OFFSET.Y, 0) + offset
		end
	end

	-- Last resort: camera position (no offset)
	return self.camera.CFrame.Position
end

-- Check if player is looking at the panel (within tolerance) and return lerp speed modifier
-- Player-follow uses anchored placement; no distance/look smoothing is applied

-- Update a single panel's position and rotation
function WorldGUIManager:_updatePanelPosition(config: PanelConfig, deltaTime: number)
	if not config.part or not config.name then
		warn(`WorldGUIManager: Panel '{config.name}' is missing part or name`)
		return
	end

	-- Camera-relative follow mode: keep panel readable in front of the camera
	local mode = (config.followMode or "player") :: any
	if mode == "target" then
		local tgt = config.followTarget
		if not tgt or not tgt.Parent then return end
		local desired: Vector3 = tgt.Position
		local off: Vector3 = config.offset or Vector3.new(0, 0, 0)
		desired += off
		local targetCF = self:_getIdealPanelRotation(desired)
		local speed = (config :: any).lerpSpeed or BASE_LERP_SPEED
		local frameRateLerp = 1 - math.exp(-speed * deltaTime)
		config.part.CFrame = config.part.CFrame:Lerp(targetCF, frameRateLerp)
		return
	end
	if mode == "camera" then
		local cam = self.camera
		if cam then
			local camCF: CFrame = cam.CFrame
			local right: Vector3 = camCF.RightVector
			local up: Vector3 = camCF.UpVector
			local look: Vector3 = camCF.LookVector
			local basePos: Vector3 = camCF.Position
			-- Per-panel forward distance: SystemPanel varies by camera mode for readability
			local forwardDist = CAMERA_PANEL_FORWARD
			if config.name == "SystemPanel" then
				if cam.CameraType == Enum.CameraType.Scriptable then
					forwardDist = CAMERA_PANEL_FORWARD_OS
				else
					forwardDist = CAMERA_PANEL_FORWARD_FREE
				end
			end
			local desired: Vector3 = basePos + right * CAMERA_PANEL_RIGHT + up * CAMERA_PANEL_UP + look * forwardDist

			-- Apply optional per-panel world offset
			local off: Vector3 = config.offset or Vector3.new(0, 0, 0)
			desired += off

			-- Apply optional camera-space offset (X=right, Y=up, Z=forward)
			local cso: Vector3 = config.camSpaceOffset or Vector3.new(0, 0, 0)
			if cso.X ~= 0 or cso.Y ~= 0 or cso.Z ~= 0 then
				desired += right * cso.X + up * cso.Y + look * cso.Z
			end

			-- Raycast to avoid placing the panel behind obstacles (including player)
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			local exclude = {}
			if self.player.Character then
				table.insert(exclude, self.player.Character)
			end
			-- Exclude the panel itself to avoid self-hits pulling it too close
			table.insert(exclude, config.part)
			params.FilterDescendantsInstances = (exclude :: any) :: { Instance }
			local toDesired = desired - basePos
			local dist = toDesired.Magnitude
			if dist > 0 then
				local hit = Workspace:Raycast(basePos, toDesired, params)
				if hit then
					-- Pull panel slightly toward camera to avoid clipping; ensure we don't end up behind the head
					local safe = math.max(hit.Distance - 0.5, 2.75)
					desired = basePos + toDesired.Unit * safe
				end
			end

			local targetCF = self:_getIdealPanelRotation(desired)
			local speed = (config :: any).lerpSpeed or BASE_LERP_SPEED
			local frameRateLerp = 1 - math.exp(-speed * deltaTime)
			config.part.CFrame = config.part.CFrame:Lerp(targetCF, frameRateLerp)
		end
		return
	end

	-- Player-follow anchored placement
	local offset: Vector3 = config.offset or Vector3.new(0, 0, 0)

	-- Adjust target position to be within the desired distance range from player
	if self.player.Character then
		local playerRootPart = self.player.Character:FindFirstChild("HumanoidRootPart")
		if playerRootPart and playerRootPart:IsA("BasePart") then
			local root: BasePart = playerRootPart
			local playerPosition: Vector3 = root.Position

			local targetPosition = playerPosition + offset

			-- Apply optional player-space offset (relative to player's local axes)
			local pso: Vector3 = (config :: any).playerSpaceOffset or Vector3.new(0, 0, 0)
			if pso.X ~= 0 or pso.Y ~= 0 or pso.Z ~= 0 then
				local r: Vector3 = root.CFrame.RightVector
				local u: Vector3 = root.CFrame.UpVector
				local f: Vector3 = root.CFrame.LookVector
				targetPosition += r * pso.X + u * pso.Y + f * pso.Z
			end

			local panelRotation: CFrame = self:_getIdealPanelRotation(targetPosition)

			-- Use delta time for frame-rate independent lerping
			local speed = (config :: any).lerpSpeed or BASE_LERP_SPEED
			local frameRateLerp = 1 - math.exp(-speed * deltaTime)

			config.part.CFrame = config.part.CFrame:Lerp(panelRotation, frameRateLerp)
		end
	end

	-- print(`🌐 WorldGUIManager: Updated panel '{config.name}' position and rotation`)
end

-- Snap a panel to its immediate target position for the current followMode (no lerp)
function WorldGUIManager:_snapPanelToTarget(config: PanelConfig)
	if not config.part or not config.name then
		return
	end
	local mode = (config.followMode or "player") :: any
	if mode == "target" then
		local tgt = config.followTarget
		if not tgt or not tgt.Parent then return end
		local desired: Vector3 = tgt.Position + (config.offset or Vector3.new(0, 0, 0))
		config.part.CFrame = self:_getIdealPanelRotation(desired)
		return
	end
	if mode == "camera" then
		local cam = self.camera
		if not cam then
			return
		end
		local camCF: CFrame = cam.CFrame
		local right: Vector3 = camCF.RightVector
		local up: Vector3 = camCF.UpVector
		local look: Vector3 = camCF.LookVector
		local basePos: Vector3 = camCF.Position
		-- Per-panel forward distance: SystemPanel varies by camera mode for readability
		local forwardDist = CAMERA_PANEL_FORWARD
		if config.name == "SystemPanel" then
			if cam.CameraType == Enum.CameraType.Scriptable then
				forwardDist = CAMERA_PANEL_FORWARD_OS
			else
				forwardDist = CAMERA_PANEL_FORWARD_FREE
			end
		end
		local desired: Vector3 = basePos
			+ right * CAMERA_PANEL_RIGHT
			+ up * CAMERA_PANEL_UP
			+ look * forwardDist
		local off: Vector3 = config.offset or Vector3.new(0, 0, 0)
		desired += off
		local cso: Vector3 = (config :: any).camSpaceOffset or Vector3.new(0, 0, 0)
		if cso.X ~= 0 or cso.Y ~= 0 or cso.Z ~= 0 then
			desired += right * cso.X + up * cso.Y + look * cso.Z
		end
		-- Raycast guard
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local exclude: { Instance } = {}
		if self.player.Character then
			table.insert(exclude, self.player.Character)
		end
		table.insert(exclude, config.part)
		params.FilterDescendantsInstances = exclude
		local toDesired = desired - basePos
		local dist = toDesired.Magnitude
		if dist > 0 then
			local hit = Workspace:Raycast(basePos, toDesired, params)
			if hit then
				local safe = math.max(hit.Distance - 0.5, 2.75)
				desired = basePos + toDesired.Unit * safe
			end
		end
		config.part.CFrame = self:_getIdealPanelRotation(desired)
		return
	end
	-- player follow (anchored)
	if not self.player.Character then
		return
	end
	local playerRootPart = self.player.Character:FindFirstChild("HumanoidRootPart")
	if not playerRootPart or not playerRootPart:IsA("BasePart") then
		return
	end
	local root: BasePart = playerRootPart
	local playerPosition: Vector3 = root.Position
	local offset: Vector3 = config.offset or Vector3.new(0, 0, 0)
	local targetPosition = playerPosition + offset
	local pso: Vector3 = (config :: any).playerSpaceOffset or Vector3.new(0, 0, 0)
	if pso.X ~= 0 or pso.Y ~= 0 or pso.Z ~= 0 then
		local r2: Vector3 = root.CFrame.RightVector
		local u2: Vector3 = root.CFrame.UpVector
		local f2: Vector3 = root.CFrame.LookVector
		targetPosition += r2 * pso.X + u2 * pso.Y + f2 * pso.Z
	end
	config.part.CFrame = self:_getIdealPanelRotation(targetPosition)
end

function WorldGUIManager:setPanelFollowTarget(panelName: string, followTarget: BasePart?)
	local cfg = self.panels[panelName]
	if not cfg then return end
	(cfg :: any).followTarget = followTarget
end

-- Adjust a panel's lerp speed at runtime
function WorldGUIManager:setPanelLerpSpeed(panelName: string, speed: number)
	local cfg = self.panels[panelName]
	if not cfg then return end
	if type(speed) ~= "number" then return end
	(cfg :: any).lerpSpeed = speed
end

-- Main update loop
function WorldGUIManager:_startUpdateLoop()
	if self.heartbeatConnection then
		self.heartbeatConnection:Disconnect()
	end

	-- Run every frame for smooth lerping
	self.heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime: number)
		for _, config in pairs(self.panels) do
			if not frozenPanels[config.name] then
				self:_updatePanelPosition(config, deltaTime)
			end
		end
	end)
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
	panelVisSeq += 1
	local opId = panelVisSeq
	panelVisOps[panelName] = opId

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

		playTweenReplace(part, TweenInfo.new(duration, Enum.EasingStyle.Quart), { Transparency = targetTransparency })
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
					playTweenReplace(child, TweenInfo.new(duration, Enum.EasingStyle.Quart), props)

					-- UIStroke borders attached to this GuiObject
					for _, deco in ipairs(child:GetChildren()) do
						if deco:IsA("UIStroke") then
							if deco:GetAttribute("OriginalStrokeTransparency") == nil then
								deco:SetAttribute("OriginalStrokeTransparency", deco.Transparency)
							end
							local oSt = deco:GetAttribute("OriginalStrokeTransparency") or 0
							local tSt = visible and oSt or 1
							playTweenReplace(
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
									if panelVisOps[panelName] == opId and not (config.visible :: any) then
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
			if panelVisOps[panelName] == opId and not (config.visible :: any) then
				if config.part and (config.part :: any).Parent then
					(config.part :: any).Parent = nil
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
function WorldGUIManager:getGUIPosition(): Vector3
	-- Return the ideal panel position for the camera to look at
	return self:_getIdealPanelPosition()
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
		frozenPanels[panelName] = true
	else
		frozenPanels[panelName] = nil :: any
	end
end

function WorldGUIManager:setPanelFollowMode(panelName: string, mode: "player" | "camera")
	local cfg = self.panels[panelName]
	if not cfg then
		return
	end
	local anyCfg: any = cfg
	anyCfg.followMode = mode
	-- Snap immediately to new target to avoid residual offsets
	self:_snapPanelToTarget(cfg)
end

function WorldGUIManager:setPanelCameraSpaceOffset(panelName: string, off: Vector3)
	local cfg = self.panels[panelName]
	if not cfg then
		return
	end
	(cfg :: any).camSpaceOffset = off
end

function WorldGUIManager:setPanelPlayerSpaceOffset(panelName: string, off: Vector3)
	local cfg = self.panels[panelName]
	if not cfg then
		return
	end
	(cfg :: any).playerSpaceOffset = off
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
	if self.heartbeatConnection then
		self.heartbeatConnection:Disconnect()
	end
	(self :: any).heartbeatConnection = nil

	-- Clean up current tween
	if self.currentTween then
		self.currentTween:Cancel()
	end
	(self :: any).currentTween = nil

	-- Clean up smooth cam part
	if self.smoothCamPart then
		self.smoothCamPart:Destroy()
	end
	(self :: any).smoothCamPart = nil

	self.panels = {}
	WorldGUIManager_Instance = nil :: any
end

-- Get the singleton instance
function WorldGUIManager.getInstance()
	return WorldGUIManager_Instance or WorldGUIManager.new()
end

return WorldGUIManager
