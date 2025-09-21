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
	setPanelVisibility: (self: WorldGUIManagerType, panelName: string, visible: boolean, duration: number?) -> (),
	destroy: (self: WorldGUIManagerType) -> (),
	_getIdealPanelPosition: (self: WorldGUIManagerType, customOffset: Vector3?) -> Vector3,
	_getIdealPanelRotation: (self: WorldGUIManagerType, panelPosition: Vector3) -> CFrame,
	_updatePanelPosition: (self: WorldGUIManagerType, config: PanelConfig, deltaTime: number) -> (),
	_isPlayerLookingAtPanel: (self: WorldGUIManagerType, config: PanelConfig) -> (boolean, number),
	_isPlayerWithinDistanceBoundaries: (self: WorldGUIManagerType, config: PanelConfig) -> (boolean, number),
	_startUpdateLoop: (self: WorldGUIManagerType) -> (),
	getGUIPosition: (self: WorldGUIManagerType) -> Vector3,
}

-- Configuration
local GUI_OFFSET = Vector3.new(0, 1.5, -3.5)
local LOOK_TOLERANCE = 5 -- Degrees of tolerance beyond panel edges before rotation starts
local MAX_DISTANCE = 4 -- Maximum distance from optimal position
local MIN_DISTANCE = 1.5 -- Minimum distance from optimal position
local BASE_LERP_SPEED = 4.0 -- Base lerp speed when far from boundaries
local MIN_LERP_SPEED = 0.5 -- Minimum lerp speed when close to boundaries
local ANGLE_TRANSITION_RANGE = 15 -- Degrees beyond tolerance where speed transitions occur

type PanelConfig = {
	name: string,
	part: BasePart,
	offset: Vector3?, -- Optional custom offset from default position
	faceCamera: boolean?, -- Whether panel should face the camera (default true)
	followPlayer: boolean?, -- Whether panel should follow player (default true)
	playerWasLooking: boolean?, -- Track if player was looking at panel
	playerWasWithinDistance: boolean?, -- Track if player was within distance boundaries
	visible: boolean?, -- Current visibility state
}

local WorldGUIManager_Instance = nil

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
	config.followPlayer = config.followPlayer ~= false -- Default true
	config.offset = config.offset or Vector3.new(0, 0, 0)
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

	-- Check current state and get lerp speed modifiers
	local isLookingAtPanel, angleLerpSpeed = self:_isPlayerLookingAtPanel(config)
	local isWithinDistance, _ = self:_isPlayerWithinDistanceBoundaries(config)

	-- Update state variables for next frame
	config.playerWasLooking = isLookingAtPanel
	-- Note: playerWasWithinDistance is already updated inside _isPlayerWithinDistanceBoundaries

	-- Skip rotation updates if player is looking at the panel AND within distance
	if isLookingAtPanel and isWithinDistance then
		return
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
		if playerRootPart then
			local playerPosition: Vector3 = playerRootPart.Position
			local playerForward: Vector3 = playerRootPart.CFrame.LookVector

			-- Target position should be at optimal distance in front of player
			local optimalDistance = (MIN_DISTANCE + MAX_DISTANCE) / 2 -- Middle of the range
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

-- Main update loop
function WorldGUIManager:_startUpdateLoop()
	if self.heartbeatConnection then
		self.heartbeatConnection:Disconnect()
	end

	-- Run every frame for smooth lerping
	self.heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime: number)
		for _, config in pairs(self.panels) do
			self:_updatePanelPosition(config, deltaTime)
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
function WorldGUIManager:setPanelVisibility(panelName: string, visible: boolean, duration: number?)
	local config = self.panels[panelName]
	if not config or not config.part then
		warn(`WorldGUIManager: Panel '{panelName}' not found`)
		return
	end

	duration = duration or 0.3

	-- Function to handle parts with original transparency
	local function tweenPartTransparency(part: BasePart)
		-- Store original transparency if not already stored
		if part:GetAttribute("OriginalTransparency") == nil then
			part:SetAttribute("OriginalTransparency", part.Transparency)
		end

		local originalTransparency = part:GetAttribute("OriginalTransparency") or 0
		local targetTransparency = visible and originalTransparency or 1

		TweenService
			:Create(part, TweenInfo.new(duration, Enum.EasingStyle.Quart), { Transparency = targetTransparency })
			:Play()
	end

	-- Tween all GUI elements in the part
	local function tweenGuiTransparency(instance: Instance)
		if instance:IsA("SurfaceGui") or instance:IsA("BillboardGui") then
			for _, child in ipairs(instance:GetDescendants()) do
				if child:IsA("GuiObject") and child:GetAttribute("OriginalTransparency") == nil then
					-- Store original transparency
					child:SetAttribute("OriginalTransparency", child.BackgroundTransparency)
				end

				if child:IsA("GuiObject") then
					local originalTransparency = child:GetAttribute("OriginalTransparency") or 0
					local newTransparency = visible and originalTransparency or 1

					TweenService:Create(
						child,
						TweenInfo.new(duration, Enum.EasingStyle.Quart),
						{ BackgroundTransparency = newTransparency }
					):Play()
				end
			end
		end
	end

	-- Tween the main part if it's a BasePart
	if config.part:IsA("BasePart") then
		tweenPartTransparency(config.part :: BasePart)
	end

	-- Tween all child parts with their original transparency
	for _, child in ipairs(config.part:GetDescendants()) do
		if child:IsA("BasePart") then
			tweenPartTransparency(child)
		end
		tweenGuiTransparency(child)
	end

	task.wait(duration)

	config.visible = visible
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
