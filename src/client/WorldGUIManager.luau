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
	_isPlayerLookingAtPanel: (self: WorldGUIManagerType, config: PanelConfig) -> (boolean, number),
	_isPlayerWithinDistanceBoundaries: (self: WorldGUIManagerType, config: PanelConfig) -> (boolean, number),
	_startUpdateLoop: (self: WorldGUIManagerType) -> (),
	getGUIPosition: (self: WorldGUIManagerType) -> Vector3,
	setPanelFrozen: (self: WorldGUIManagerType, panelName: string, frozen: boolean) -> (),
	setPanelFollowMode: (self: WorldGUIManagerType, panelName: string, mode: "player" | "camera") -> (),
	_snapPanelToTarget: (self: WorldGUIManagerType, config: PanelConfig) -> (),
}

-- Configuration
local GUI_OFFSET = Vector3.new(0, 1.5, -3.5)
-- Camera-relative placement for panels that should follow the camera rather than the player
local CAMERA_PANEL_FORWARD = 4.0 -- studs in front of camera
local CAMERA_PANEL_RIGHT = 0.0 -- shift to the right (positive) or left (negative)
local CAMERA_PANEL_UP = -0.25 -- slight downward offset to better frame content
local LOOK_TOLERANCE = 5 -- Degrees of tolerance beyond panel edges before rotation starts
local MAX_DISTANCE = 4 -- Maximum distance from optimal position
local MIN_DISTANCE = 1.5 -- Minimum distance from optimal position
local BASE_LERP_SPEED = 4.0 -- Base lerp speed when far from boundaries
local MIN_LERP_SPEED = 0.5 -- Minimum lerp speed when close to boundaries
local ANGLE_TRANSITION_RANGE = 15 -- Degrees beyond tolerance where speed transitions occur

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
	faceCamera: boolean?, -- Whether panel should face the camera (default true)
	followPlayer: boolean?, -- Legacy: Whether panel should follow player (default true)
	followMode: "player" | "camera"?, -- New: explicit follow mode (default "player")
	playerWasLooking: boolean?, -- Track if player was looking at panel
	playerWasWithinDistance: boolean?, -- Track if player was within distance boundaries
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
	config.followPlayer = config.followPlayer ~= false -- Default true (legacy)
	-- Default followMode derived from legacy flag when not provided
	local derivedMode: "player" | "camera" = if config.followPlayer then "player" else "camera"
	config.followMode = config.followMode or derivedMode
	config.offset = config.offset or Vector3.new(0, 0, 0)
	config.camSpaceOffset = config.camSpaceOffset or Vector3.new(0, 0, 0)
	config.playerWasLooking = false
	config.playerWasWithinDistance = false
	config.visible = false

	self.panels[config.name] = config

	-- Initial positioning (use 1/60 as default deltaTime for initial setup)
	self:_updatePanelPosition(config, 1 / 60)

	print(`🌐 WorldGUIManager: Registered panel '{config.name}'`)
end

-- Unregister a panel
function WorldGUIManager:unregisterPanel(name: string)
	if self.panels[name] then
		self.panels[name] = nil
		print(`🌐 WorldGUIManager: Unregistered panel '{name}'`)
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
function WorldGUIManager:_isPlayerLookingAtPanel(config: PanelConfig): (boolean, number)
	if not config.part or not self.camera then
		return false, BASE_LERP_SPEED
	end

	local cameraPosition = self.camera.CFrame.Position
	local cameraLookDirection = self.camera.CFrame.LookVector

	-- Get panel bounds (left and right edges)
	local panelCFrame = config.part.CFrame
	local panelSize = config.part.Size

	-- Calculate left and right edge positions in world space
	local leftEdge = panelCFrame * Vector3.new(-panelSize.X / 2, 0, 0)
	local rightEdge = panelCFrame * Vector3.new(panelSize.X / 2, 0, 0)

	-- Calculate angles to left and right edges
	local cameraToLeftEdge = (leftEdge - cameraPosition).Unit
	local cameraToRightEdge = (rightEdge - cameraPosition).Unit

	-- Project onto horizontal plane for angle calculation
	local horizontalLookDirection = Vector3.new(cameraLookDirection.X, 0, cameraLookDirection.Z).Unit
	local horizontalToLeftEdge = Vector3.new(cameraToLeftEdge.X, 0, cameraToLeftEdge.Z).Unit
	local horizontalToRightEdge = Vector3.new(cameraToRightEdge.X, 0, cameraToRightEdge.Z).Unit

	-- Calculate signed angles using cross product to determine left/right
	local function getSignedAngle(from: Vector3, to: Vector3): number
		local dot = math.clamp(from:Dot(to), -1, 1)
		local angle = math.deg(math.acos(dot))
		local cross = from:Cross(to)
		return cross.Y > 0 and angle or -angle
	end

	local angleToLeftEdge = getSignedAngle(horizontalLookDirection, horizontalToLeftEdge)
	local angleToRightEdge = getSignedAngle(horizontalLookDirection, horizontalToRightEdge)

	-- Calculate how far past the edge + tolerance we are looking
	local leftOvershoot = math.max(0, angleToLeftEdge - LOOK_TOLERANCE)
	local rightOvershoot = math.max(0, -angleToRightEdge - LOOK_TOLERANCE)

	-- Use the maximum overshoot to determine speed
	local maxOvershoot = math.max(leftOvershoot, rightOvershoot)

	-- Calculate lerp speed based on overshoot
	local lerpSpeed: number
	if maxOvershoot <= ANGLE_TRANSITION_RANGE then
		-- Linear falloff from MIN_LERP_SPEED to BASE_LERP_SPEED
		local normalizedOvershoot = maxOvershoot / ANGLE_TRANSITION_RANGE
		lerpSpeed = MIN_LERP_SPEED + (BASE_LERP_SPEED - MIN_LERP_SPEED) * normalizedOvershoot
	else
		-- Full speed when far from edges
		lerpSpeed = BASE_LERP_SPEED
	end

	-- Player is looking at panel if:
	-- - Looking past left edge (negative angle to left edge)
	-- - Looking past right edge (positive angle to right edge)
	-- - Both conditions are true simultaneously
	local lookingPastLeftEdge = false
	local lookingPastRightEdge = false

	if config.playerWasLooking then
		lookingPastLeftEdge = angleToLeftEdge > LOOK_TOLERANCE
		lookingPastRightEdge = angleToRightEdge < -LOOK_TOLERANCE
	else
		lookingPastLeftEdge = angleToLeftEdge > 0
		lookingPastRightEdge = angleToRightEdge < 0
	end

	-- Player is looking at panel if they're NOT looking past both edges
	local isLooking = not (lookingPastLeftEdge or lookingPastRightEdge)

	return isLooking, lerpSpeed
end

function WorldGUIManager:_isPlayerWithinDistanceBoundaries(config: PanelConfig): (boolean, number)
	if not config.part or not self.player.Character then
		return false, BASE_LERP_SPEED
	end

	local playerRootPart = self.player.Character:FindFirstChild("HumanoidRootPart")
	if not playerRootPart then
		return false, BASE_LERP_SPEED
	end

	-- Check if panel is in front of or behind the player
	local playerPosition = playerRootPart.Position
	local playerForward = playerRootPart.CFrame.LookVector
	local panelPosition = config.part.Position

	-- Vector from player to panel
	local playerToPanel = (panelPosition - playerPosition)
	local distanceToPlayer = playerToPanel.Magnitude

	-- Project onto player's forward direction to see if panel is in front or behind
	local forwardDot = playerToPanel.Unit:Dot(playerForward)
	local isInFront = forwardDot > 0

	-- Always use full speed for distance-based movements
	local lerpSpeed = BASE_LERP_SPEED

	-- Calculate if within boundaries (with hysteresis)
	local withinBoundaries = false
	if config.playerWasWithinDistance then
		-- If player was within distance last time, check if still within boundaries
		-- Panel should be in front and within distance range
		withinBoundaries = isInFront and distanceToPlayer <= MAX_DISTANCE and distanceToPlayer >= MIN_DISTANCE
	else
		-- If player was not within distance last time, check if now within boundaries
		-- Use tighter boundaries to prevent jitter
		withinBoundaries = isInFront
			and distanceToPlayer <= MAX_DISTANCE - 0.5
			and distanceToPlayer >= MIN_DISTANCE + 0.5
	end

	config.playerWasWithinDistance = withinBoundaries

	return withinBoundaries, lerpSpeed
end

-- Update a single panel's position and rotation
function WorldGUIManager:_updatePanelPosition(config: PanelConfig, deltaTime: number)
	if not config.part or not config.name then
		warn(`WorldGUIManager: Panel '{config.name}' is missing part or name`)
		return
	end

	-- Camera-relative follow mode: keep panel readable in front of the camera
	local mode = (config.followMode or (config.followPlayer and "player" or "camera")) :: any
	if mode == "camera" then
		local cam = self.camera
		if cam then
			local camCF: CFrame = cam.CFrame
			local right: Vector3 = camCF.RightVector
			local up: Vector3 = camCF.UpVector
			local look: Vector3 = camCF.LookVector
			local basePos: Vector3 = camCF.Position
			-- Per-panel forward distance: SystemPanel is a bit closer in OS (Scriptable) for readability
			local forwardDist = CAMERA_PANEL_FORWARD
			if config.name == "SystemPanel" and cam.CameraType == Enum.CameraType.Scriptable then
				forwardDist = 3.0
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
			local frameRateLerp = 1 - math.exp(-BASE_LERP_SPEED * deltaTime)
			config.part.CFrame = config.part.CFrame:Lerp(targetCF, frameRateLerp)
		end
		return
	end

	-- Check current state and get lerp speed modifiers
	local isLookingAtPanel, angleLerpSpeed = self:_isPlayerLookingAtPanel(config)
	local isWithinDistance, _ = self:_isPlayerWithinDistanceBoundaries(config)

	-- Update state variables for next frame
	config.playerWasLooking = isLookingAtPanel
	-- Note: playerWasWithinDistance is already updated inside _isPlayerWithinDistanceBoundaries

	-- Skip rotation updates if player is looking at the panel AND within distance
	-- Exception: always update the SystemPanel to keep it anchored during OS focus
	if config.name ~= "SystemPanel" then
		if isLookingAtPanel and isWithinDistance then
			return
		end
	end

	-- Determine the reason for rotation and apply appropriate speed
	local dynamicLerpSpeed: number
	if not isLookingAtPanel and isWithinDistance then
		-- Rotating because player looked away (angle boundary) - use slow speed
		dynamicLerpSpeed = angleLerpSpeed
	else
		-- Rotating because player moved away (distance boundary) - use full speed
		dynamicLerpSpeed = BASE_LERP_SPEED
	end -- Calculate ideal rotation
	local offset: Vector3 = config.offset or Vector3.new(0, 0, 0)

	-- Adjust target position to be within the desired distance range from player
	if self.player.Character then
		local playerRootPart = self.player.Character:FindFirstChild("HumanoidRootPart")
		if playerRootPart and playerRootPart:IsA("BasePart") then
			local root: BasePart = playerRootPart
			local playerPosition: Vector3 = root.Position
			local playerForward: Vector3 = root.CFrame.LookVector

			-- Target position should be at optimal distance in front of player
			local optimalDistance = (MIN_DISTANCE + MAX_DISTANCE) / 2 -- Middle of the range
			if config.name == "SystemPanel" then
				optimalDistance = 2.75 -- consistent comfortable distance for OS
			end
			local targetPosition = playerPosition
				+ playerForward * optimalDistance
				+ Vector3.new(0, GUI_OFFSET.Y, 0)
				+ offset

			local panelRotation: CFrame = self:_getIdealPanelRotation(targetPosition)

			-- Use delta time for frame-rate independent lerping with dynamic speed
			local frameRateLerp = 1 - math.exp(-dynamicLerpSpeed * deltaTime)

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
	local mode = (config.followMode or (config.followPlayer and "player" or "camera")) :: any
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
		local desired: Vector3 = basePos
			+ right * CAMERA_PANEL_RIGHT
			+ up * CAMERA_PANEL_UP
			+ look * CAMERA_PANEL_FORWARD
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
	-- player follow
	if not self.player.Character then
		return
	end
	local playerRootPart = self.player.Character:FindFirstChild("HumanoidRootPart")
	if not playerRootPart or not playerRootPart:IsA("BasePart") then
		return
	end
	local root: BasePart = playerRootPart
	local playerPosition: Vector3 = root.Position
	local playerForward: Vector3 = root.CFrame.LookVector
	local optimalDistance = (MIN_DISTANCE + MAX_DISTANCE) / 2
	if config.name == "SystemPanel" then
		optimalDistance = 2.75
	end
	local offset: Vector3 = config.offset or Vector3.new(0, 0, 0)
	local targetPosition = playerPosition + playerForward * optimalDistance + Vector3.new(0, GUI_OFFSET.Y, 0) + offset
	config.part.CFrame = self:_getIdealPanelRotation(targetPosition)
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
	print("🔄 WorldGUIManager: Panel position reset")
end

-- Get the GUI panel position for camera targeting
function WorldGUIManager:getGUIPosition(): Vector3
	-- Return the ideal panel position for the camera to look at
	return self:_getIdealPanelPosition()
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
	-- Reset hysteresis flags to avoid carry-over artifacts when switching modes
	anyCfg.playerWasLooking = false
	anyCfg.playerWasWithinDistance = false
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
