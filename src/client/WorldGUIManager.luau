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
	_updatePanelPosition: (self: WorldGUIManagerType, config: PanelConfig) -> (),
	_startUpdateLoop: (self: WorldGUIManagerType) -> (),
	_createSmoothCamPart: (self: WorldGUIManagerType) -> (),
	getGUIPosition: (self: WorldGUIManagerType) -> Vector3,
}

-- Configuration
local GUI_OFFSET = Vector3.new(0, 1.5, -3.5) -- Left, Up, Forward from player
local TARGET_UPDATE_FREQUENCY = 1 / 15 -- Calculate new targets 15 times per second
local PANEL_DISTANCE = 3.5 -- Distance from camera where panel should be positioned
local MAX_ANGLE_FROM_LOOK = 45 -- Max degrees panel can be from look direction before repositioning
local ANGLE_HYSTERESIS = 15 -- Extra angle buffer to prevent oscillation (degrees)
local DISTANCE_HYSTERESIS = 0.5 -- Extra buffer to prevent oscillation (studs)

-- Smooth movement parameters (inspired by the smooth camera approach)
local TWEEN_TIME_NORMAL = 0.4 -- Faster normal movement speed
local TWEEN_TIME_REPOSITIONING = 0.6 -- Faster repositioning
local EASING_STYLE = Enum.EasingStyle.Quart -- Smooth easing
local EASING_DIRECTION = Enum.EasingDirection.Out -- Ease out for natural feel

-- Calculate min/max distances based on GUI_OFFSET magnitude with hysteresis
local PREFERRED_DISTANCE = GUI_OFFSET.Magnitude
local MIN_PLAYER_DISTANCE = PREFERRED_DISTANCE - 0.8 -- Tighter minimum distance
local MAX_PLAYER_DISTANCE = PREFERRED_DISTANCE + 1
-- Hysteresis bounds (tighter range for stopping repositioning - harder to trigger again)
local MIN_PLAYER_DISTANCE_HYSTERESIS = MIN_PLAYER_DISTANCE + DISTANCE_HYSTERESIS -- Closer to center
local MAX_PLAYER_DISTANCE_HYSTERESIS = MAX_PLAYER_DISTANCE - DISTANCE_HYSTERESIS -- Closer to center

print(
	`🔧 Distance bounds: Normal [{MIN_PLAYER_DISTANCE} - {MAX_PLAYER_DISTANCE}], Hysteresis [{MIN_PLAYER_DISTANCE_HYSTERESIS} - {MAX_PLAYER_DISTANCE_HYSTERESIS}]`
)

-- Angle hysteresis bounds
local MAX_ANGLE_FROM_LOOK_HYSTERESIS = MAX_ANGLE_FROM_LOOK - ANGLE_HYSTERESIS -- Tighter bound for stopping repositioning

type PanelConfig = {
	name: string,
	part: BasePart,
	offset: Vector3?, -- Optional custom offset from default position
	faceCamera: boolean?, -- Whether panel should face the camera (default true)
	followPlayer: boolean?, -- Whether panel should follow player (default true)
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
	self.idealPanelPosition = nil :: Vector3? -- Current ideal position for the panel
	self.isRepositioning = false -- Track if we're currently in repositioning mode
	self.lastTargetUpdateTime = 0
	self.cachedTargetPosition = nil :: Vector3?
	self.cachedTargetRotation = nil :: CFrame?
	self.smoothCamPart = nil :: BasePart?
	self.lastAngleBetween = nil :: number?
	self.currentTween = nil :: Tween?

	self:_createSmoothCamPart()
	self:_startUpdateLoop()

	-- Handle character respawning
	self.player.CharacterAdded:Connect(function()
		wait(1) -- Wait for character to fully load
		self:_createSmoothCamPart()
		print("🔄 Recreated smooth camera part for new character")
	end)

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

	self.panels[config.name] = config

	-- Initial positioning
	self:_updatePanelPosition(config)

	print(`🌐 WorldGUIManager: Registered panel '{config.name}'`)
end

-- Unregister a panel
function WorldGUIManager:unregisterPanel(name: string)
	if self.panels[name] then
		self.panels[name] = nil
		print(`🌐 WorldGUIManager: Unregistered panel '{name}'`)
	end
end

-- Create a smooth camera part for buttery movement (inspired by smooth camera systems)
function WorldGUIManager:_createSmoothCamPart()
	-- Clean up existing smooth cam part
	if self.smoothCamPart then
		self.smoothCamPart:Destroy()
	end

	local character = self.player.Character
	if not character then
		return
	end

	-- Create invisible part for smooth movement
	local smoothCam = Instance.new("Part")
	smoothCam.Name = "WorldGUI_SmoothCam"
	smoothCam.Transparency = 1
	smoothCam.Anchored = true
	smoothCam.CanCollide = false
	smoothCam.Size = Vector3.new(0.1, 0.1, 0.1)
	smoothCam.Parent = character

	self.smoothCamPart = smoothCam

	-- Set initial position
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart and self.smoothCamPart then
		local initialPosition = (rootPart.CFrame * CFrame.new(GUI_OFFSET)).Position
		self.smoothCamPart.Position = initialPosition
	end

	print("🎥 Created smooth camera part for buttery GUI movement")
end

-- Get the ideal position for a panel relative to player
function WorldGUIManager:_getIdealPanelPosition(customOffset: Vector3?): Vector3
	local character = self.player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then
		return Vector3.new(0, 0, 0)
	end

	local rootPart = character.HumanoidRootPart :: BasePart
	local cameraPosition = self.camera.CFrame.Position :: Vector3
	local cameraLookDirection = self.camera.CFrame.LookVector :: Vector3

	-- Calculate the default panel position (where it would naturally be)
	local playerCFrame = rootPart.CFrame
	local defaultPanelPosition = (playerCFrame * CFrame.new(GUI_OFFSET)).Position

	-- Set initial ideal position if not set
	if not self.idealPanelPosition then
		self.idealPanelPosition = defaultPanelPosition
		print("🎯 WorldGUIManager: Initial panel position set")
		return defaultPanelPosition
	end

	-- Calculate angle between look direction and current panel position
	local cameraToPanel = (self.idealPanelPosition - cameraPosition).Unit
	local horizontalLookDirection = Vector3.new(cameraLookDirection.X, 0, cameraLookDirection.Z).Unit
	local horizontalCameraToPanel = Vector3.new(cameraToPanel.X, 0, cameraToPanel.Z).Unit

	local angleBetween = math.deg(math.acos(math.clamp(horizontalLookDirection:Dot(horizontalCameraToPanel), -1, 1)))

	-- Calculate distance between panel and player
	local playerPosition = rootPart.Position
	local panelToPlayerDistance = (self.idealPanelPosition - playerPosition).Magnitude

	-- Use hysteresis for distance checking to prevent oscillation
	local distanceOutOfBounds
	if self.isRepositioning then
		-- We're already repositioning - use wider hysteresis bounds to stop repositioning
		distanceOutOfBounds = panelToPlayerDistance < MIN_PLAYER_DISTANCE_HYSTERESIS
			or panelToPlayerDistance > MAX_PLAYER_DISTANCE_HYSTERESIS
	else
		-- We're not repositioning - use normal bounds to start repositioning
		distanceOutOfBounds = panelToPlayerDistance < MIN_PLAYER_DISTANCE or panelToPlayerDistance > MAX_PLAYER_DISTANCE
	end

	-- Use hysteresis for angle checking to prevent oscillation
	local angleOutOfBounds
	if self.isRepositioning then
		-- We're already repositioning - check if player is looking towards panel
		local isLookingTowardsPanel = false
		if self.lastAngleBetween then
			-- If angle is decreasing, player is looking towards panel
			local lastAngle: number = self.lastAngleBetween
			isLookingTowardsPanel = angleBetween < lastAngle - 2 -- 2 degree buffer
		end

		if isLookingTowardsPanel then
			-- Player is actively looking towards panel - stop repositioning immediately
			angleOutOfBounds = false
			print(`👀 Player looking towards panel - stopping repositioning (angle: {math.floor(angleBetween)}°)`)
		else
			-- Use wider hysteresis bound to stop repositioning
			angleOutOfBounds = angleBetween > MAX_ANGLE_FROM_LOOK_HYSTERESIS
		end
	else
		-- We're not repositioning - use normal bound to start repositioning
		angleOutOfBounds = angleBetween > MAX_ANGLE_FROM_LOOK
	end

	-- Store current angle for next frame comparison
	self.lastAngleBetween = angleBetween

	-- Check if panel needs repositioning (either angle or distance out of bounds)
	local needsRepositioning = angleOutOfBounds or distanceOutOfBounds

	if needsRepositioning then
		if not self.isRepositioning then
			print(
				`🔄 Starting repositioning (angle: {math.floor(angleBetween)}°/{MAX_ANGLE_FROM_LOOK}°, distance: {math.floor(
					panelToPlayerDistance
				)}/{PREFERRED_DISTANCE} studs)`
			)
		end
		self.isRepositioning = true

		if angleOutOfBounds then
			-- Panel is outside acceptable view angle - move to boundary
			local cross = horizontalLookDirection:Cross(horizontalCameraToPanel)
			local angleSign = cross.Y > 0 and 1 or -1 -- Which side of look direction

			-- Create rotation to the max allowed angle
			local maxAngleRad = math.rad(MAX_ANGLE_FROM_LOOK)
			local rotationCFrame = CFrame.fromAxisAngle(Vector3.new(0, 1, 0), angleSign * maxAngleRad)
			local boundaryDirection = rotationCFrame * horizontalLookDirection

			-- Position panel at the boundary, but at player's current Y level + offset
			local newHorizontalPosition = cameraPosition + (boundaryDirection * PANEL_DISTANCE)
			local playerY = rootPart.Position.Y + GUI_OFFSET.Y
			self.idealPanelPosition = Vector3.new(newHorizontalPosition.X, playerY, newHorizontalPosition.Z)

			print(`📍 Panel repositioned to view boundary (angle was {math.floor(angleBetween)}°)`)
		elseif distanceOutOfBounds then
			-- Panel is too far/close to player - move to default position
			self.idealPanelPosition = defaultPanelPosition
			print(`📏 Panel repositioned due to distance (was {math.floor(panelToPlayerDistance)} studs from player)`)
		end
	else
		-- No repositioning needed - stop repositioning mode
		if self.isRepositioning then
			print(
				`✅ Repositioning stopped (angle: {math.floor(angleBetween)}°/{MAX_ANGLE_FROM_LOOK_HYSTERESIS}°, distance: {math.floor(
					panelToPlayerDistance
				)} studs)`
			)
		end
		self.isRepositioning = false
	end
	-- If angle <= MAX_ANGLE_FROM_LOOK, keep the panel where it is (don't move it)

	-- Apply custom offset if provided
	local finalPosition = self.idealPanelPosition
	if customOffset then
		finalPosition = finalPosition + customOffset
	end

	return finalPosition
end

-- Get the ideal rotation for a panel to face the camera
function WorldGUIManager:_getIdealPanelRotation(panelPosition: Vector3): CFrame
	local cameraPosition = self.camera.CFrame.Position :: Vector3

	-- Make panel face the camera
	local lookDirection = (cameraPosition - panelPosition).Unit

	-- Create CFrame that faces the camera with up vector pointing up
	return CFrame.lookAt(panelPosition, panelPosition + lookDirection, Vector3.new(0, 1, 0))
end

-- Update a single panel's position and rotation
function WorldGUIManager:_updatePanelPosition(config: PanelConfig)
	if not config.part or not config.part.Parent then
		return
	end

	local currentTime = tick()

	-- Update target positions at a slower rate
	if not self.cachedTargetPosition or currentTime - self.lastTargetUpdateTime >= TARGET_UPDATE_FREQUENCY then
		self.lastTargetUpdateTime = currentTime
		self.cachedTargetPosition = self:_getIdealPanelPosition(config.offset)
		if config.faceCamera and self.cachedTargetPosition then
			self.cachedTargetRotation = self:_getIdealPanelRotation(self.cachedTargetPosition)
		end
	end

	-- Use smooth camera part approach for buttery movement
	if config.followPlayer and self.cachedTargetPosition and self.smoothCamPart then
		local targetPosition: Vector3 = self.cachedTargetPosition
		local currentPosition: Vector3 = self.smoothCamPart.Position

		-- Check if we need to move the smooth cam part - reduced threshold for more responsiveness
		local distance = (targetPosition - currentPosition).Magnitude
		if distance > 0.05 then -- Much smaller threshold for instant response
			-- Stop any current tween to prevent conflicts
			if self.currentTween then
				self.currentTween:Cancel()
			end

			-- Choose tween time based on whether we're repositioning and distance
			local tweenTime = self.isRepositioning and TWEEN_TIME_REPOSITIONING or TWEEN_TIME_NORMAL

			-- Make it faster if we're getting too close to prevent walking through
			if distance > 2 then -- Large distance change (like repositioning)
				tweenTime = tweenTime * 0.7 -- Faster for large movements
			end

			-- Create smooth tween to new position
			self.currentTween = TweenService:Create(
				self.smoothCamPart,
				TweenInfo.new(tweenTime, EASING_STYLE, EASING_DIRECTION),
				{ Position = targetPosition }
			)
			self.currentTween:Play()
		end

		-- Panel follows the smooth cam part position
		config.part.Position = self.smoothCamPart.Position
	end

	-- Simple lerp for rotation (smooth enough as-is)
	if config.faceCamera and self.cachedTargetRotation then
		local currentCFrame = config.part.CFrame
		local newCFrame = currentCFrame:Lerp(self.cachedTargetRotation, 0.1)
		config.part.CFrame = newCFrame
	end
end

-- Main update loop
function WorldGUIManager:_startUpdateLoop()
	if self.heartbeatConnection then
		self.heartbeatConnection:Disconnect()
	end

	-- Run every frame for smooth lerping
	self.heartbeatConnection = RunService.Heartbeat:Connect(function()
		for _, config in pairs(self.panels) do
			self:_updatePanelPosition(config)
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
