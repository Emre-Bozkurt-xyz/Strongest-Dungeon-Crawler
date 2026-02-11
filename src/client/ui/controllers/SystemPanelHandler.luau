--!strict
-- Client-side system panel handler for displaying stats and attributes

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HealthBarController = require(script.Parent.HealthBarController)
local ManaBarController = require(script.Parent.ManaBarController)
local StaminaBarController = require(script.Parent.StaminaBarController)
local AttributesUIController = require(script.Parent.AttributesUIController)
local WorldGUIManager = require(script.Parent.Parent.Parent.WorldGUIManager)
local StatusPreviewController = require(script.Parent.StatusPreviewController)
local InventoryUIController = require(script.Parent.InventoryUIController)

local SystemPanelHandler = {}
SystemPanelHandler.__index = SystemPanelHandler

-- System panel placement tuning (single source of truth)
local SYSTEM_PANEL_OFFSET = Vector3.new(0, 0.2, 0)
local SYSTEM_PANEL_PLAYER_OFFSET = Vector3.new(0.3, 1.0, 3.8)
local SYSTEM_PANEL_FACE_BLEND = 0.35
local SYSTEM_PANEL_LERP_SPEED = 14
local SYSTEM_PANEL_MIN_RADIUS = 2.7
local SYSTEM_PANEL_MAX_RADIUS = 8.0
local SYSTEM_PANEL_PLAYER_OFFSET_MODE = "yaw"
local SYSTEM_PANEL_RADIUS_PADDING_FLOOR = 0.5
local SYSTEM_PANEL_LAYOUT_WEIGHT = 2.25

-- Import clients for centralized data access
local AttributesClient = require(script.Parent.Parent.Parent.AttributesClient)
local StatsClient = require(script.Parent.Parent.Parent.StatsClient)

function SystemPanelHandler.new()
	local self = setmetatable({}, SystemPanelHandler)

	-- Create the system panel
	self.systemPanel = ReplicatedStorage.Assets.WorldUI.SystemPanel:Clone()
	local radiusPadding = SYSTEM_PANEL_RADIUS_PADDING_FLOOR
	if self.systemPanel and self.systemPanel:IsA("BasePart") then
		radiusPadding = math.max(radiusPadding, self.systemPanel.Size.Z * 0.5)
	end

	-- Initialize UI controllers
	self.statusPanel = self.systemPanel:FindFirstChild("StatusPanel", true)
	self.attributesPanel = self.systemPanel:FindFirstChild("AttributesPanel", true)
	self.infoPanel = self.systemPanel:FindFirstChild("InfoPanel", true)
	if self.statusPanel and self.attributesPanel then
		self.staminaBarController = StaminaBarController.new(self.statusPanel)
		self.healthBarController = HealthBarController.new(self.statusPanel)
		self.manaBarController = ManaBarController.new(self.statusPanel)
		self.attributesUIController = AttributesUIController.new(self.attributesPanel)
	end

	-- Register panel with WorldGUIManager for positioning
	local worldGUIManager = WorldGUIManager.getInstance()
	worldGUIManager:setGroupParams("menu", {
		lerpSpeed = SYSTEM_PANEL_LERP_SPEED,
		minRadius = SYSTEM_PANEL_MIN_RADIUS,
		maxRadius = SYSTEM_PANEL_MAX_RADIUS,
		radiusPadding = radiusPadding,
		playerOffsetMode = SYSTEM_PANEL_PLAYER_OFFSET_MODE,
		centerWeights = {
			SystemPanel = SYSTEM_PANEL_LAYOUT_WEIGHT,
			_default = 1,
		},
	})
	worldGUIManager:registerPanel({
		name = "SystemPanel",
		part = self.systemPanel,
		group = "menu",
		faceCamera = true,
		faceMode = "playerYaw",
		faceBlend = SYSTEM_PANEL_FACE_BLEND,
		followMode = "player",
		offset = SYSTEM_PANEL_OFFSET, -- slight lift
		playerSpaceOffset = SYSTEM_PANEL_PLAYER_OFFSET, -- slightly left, in front of player
		playerOffsetMode = SYSTEM_PANEL_PLAYER_OFFSET_MODE,
		radiusPadding = radiusPadding,
	})

	-- Listen for stats updates via StatsClient change signal
	self._statsConn = StatsClient.onChanged(function()
		task.defer(function()
			local statsData = StatsClient.getFormattedStats()
			if statsData then
				self:updateStats(statsData)
			end
		end)
	end)

	-- Listen for attributes updates via dispatcher-backed client
	local function attrListener(ctx: any)
		self:updateAttributes(ctx.data)
	end
	self._attrConn = AttributesClient.onChanged(function(data, source, trace)
		attrListener({ data = data, source = source, trace = trace })
	end)

	-- Initial update to get current data
	local function initialUpdate()
		-- Update stats
		local statsData = StatsClient.getFormattedStats()
		if statsData then
			self:updateStats(statsData)
			-- Also update status preview
			StatusPreviewController.updateStats(statsData)
		end

		-- Update attributes
		local attributeData = AttributesClient.getFormattedAttributes()
		if attributeData then
			self:updateAttributes(attributeData)
		end
	end

	-- Do initial update after a short delay
	task.wait(0.1)
	initialUpdate()

	self._cameraModId = nil
	self._menuView = "system"
	self._menuOpen = false

	return self
end

function SystemPanelHandler:updateStats(newStats)
	-- Logic to update stats in the system panel
	if not self.systemPanel then
		warn("System panel not initialized")
		return
	end

	-- Defensive checks for stats objects
	if newStats.Health and newStats.Health.getCurrentValue and newStats.Health.getValue then
		self.healthBarController:updateHealth(newStats.Health:getCurrentValue(), newStats.Health:getValue())
	end

	if newStats.Mana and newStats.Mana.getCurrentValue and newStats.Mana.getValue then
		self.manaBarController:updateMana(newStats.Mana:getCurrentValue(), newStats.Mana:getValue())
	end

	if newStats.Stamina and newStats.Stamina.getCurrentValue and newStats.Stamina.getValue then
		self.staminaBarController:updateStamina(newStats.Stamina:getCurrentValue(), newStats.Stamina:getValue())
	end

	-- Mirror to status preview as well
	StatusPreviewController.updateStats(newStats)
end

function SystemPanelHandler:updateAttributes(attributes)
	-- Logic to update attributes in the system panel
	if not self.attributesUIController then
		warn("Attributes UI Controller not initialized")
		return
	end

	self.attributesUIController:updateAttributes(attributes)
end

function SystemPanelHandler:setMenuView(view: string)
	self._menuView = view
	local worldGUIManager = WorldGUIManager.getInstance()
	if self._menuOpen then
		local showSystem = view == "system"
		worldGUIManager:setPanelVisibility("SystemPanel", showSystem, 0.2, workspace)
	end
	local invUI = InventoryUIController.tryInit()
	if invUI and invUI.setMenuView then
		invUI:setMenuView(view)
	end
end

function SystemPanelHandler:cycleMenuView(direction: number?)
	local worldGUIManager = WorldGUIManager.getInstance()
	if not worldGUIManager:isPanelVisible("SystemPanel") then
		return
	end
	local invUI = InventoryUIController.tryInit()
	if invUI and invUI.cycleMenuView then
		local nextView = invUI:cycleMenuView(direction or 1)
		self._menuView = nextView
	end
end

function SystemPanelHandler:togglePanel()
	-- Toggle visibility of the system panel
	if not self.systemPanel then
		warn("System panel not initialized")
		return
	end
	local worldGUIManager = WorldGUIManager.getInstance()
	local isVisible = worldGUIManager:isPanelVisible("SystemPanel")
	if isVisible then
		self:hidePanel()
	else
		self:displayPanel()
	end
end

function SystemPanelHandler:displayPanel()
	-- WorldGUIManager handles positioning, we just need to place it in workspace
	if not self.systemPanel then
		warn("System panel not initialized")
		return
	end

	-- Use WorldGUIManager visibility controls (it will handle parenting)
	local worldGUIManager = WorldGUIManager.getInstance()
	worldGUIManager:setPanelFollowMode("SystemPanel", "player")
	worldGUIManager:setPanelFollowModeLock("SystemPanel", true)
	worldGUIManager:setPanelPlayerSpaceOffset("SystemPanel", SYSTEM_PANEL_PLAYER_OFFSET)
	self._menuOpen = true

	-- Hide status preview while system panel is shown
	worldGUIManager:setPanelVisibility("StatusPreview", false, 0.2, workspace)
	local invUI = InventoryUIController.tryInit()
	if invUI then
		invUI:setMenuView(self._menuView)
	end
	self:setMenuView(self._menuView)

	local CameraController = require(script.Parent.Parent.Parent.CameraController)
	local cam = CameraController.getInstance()
	cam:clearFocus()
	if self._cameraModId then
		cam:popModifier(self._cameraModId)
		self._cameraModId = nil
	end
	self._cameraModId = cam:pushModifier({
		priority = 50,
		followSmoothness = 0.75,
		lookSmoothness = 0.7,
		shoulderRight = 2.8,
		shoulderUp = 2.25,
		shoulderBack = 4.8,
		fov = 65,
		lockYaw = true,
		lockPitch = true,
		yawAssist = {
			maxYaw = math.rad(50),
			deadzone = 0.12,
			smoothness = 0.14,
		},
		lookAtProvider = function()
			local wg = WorldGUIManager.getInstance()
			if wg then
				return wg:getGUIPosition()
			end
			return nil
		end,
	})
end

function SystemPanelHandler:hidePanel()
	-- Use WorldGUIManager for smooth hiding (it will handle unparenting after fade)
	local worldGUIManager = WorldGUIManager.getInstance()
	self._menuOpen = false
	worldGUIManager:setPanelFollowModeLock("SystemPanel", false)
	worldGUIManager:setPanelFollowMode("SystemPanel", "camera")
	worldGUIManager:setPanelVisibility("SystemPanel", false, 0.5, workspace)

	-- Show status preview again
	worldGUIManager:setPanelVisibility("StatusPreview", true, 0.2, workspace)
	local invUI = InventoryUIController.tryInit()
	if invUI then
		invUI:hideAll()
	end

	local CameraController = require(script.Parent.Parent.Parent.CameraController)
	local cam = CameraController.getInstance()
	cam:clearFocus()
	if self._cameraModId then
		cam:popModifier(self._cameraModId)
		self._cameraModId = nil
	end
end

function SystemPanelHandler:toggleMenuView(view: string)
	if not self._menuOpen then
		self._menuView = view
		self:displayPanel()
		return
	end

	if self._menuView == view then
		self:hidePanel()
		return
	end

	self:setMenuView(view)
end

function SystemPanelHandler:togglePreview()
	-- Temporarily hide attribute and info panels to show only status bars
	if not self.attributesPanel or not self.infoPanel then
		warn("Attributes or Info panel not initialized")
		return
	end
	local currentlyVisible = self.attributesPanel.Visible or self.infoPanel.Visible
	self.attributesPanel.Visible = not currentlyVisible
	self.infoPanel.Visible = not currentlyVisible
end

-- Lazy singleton facade so callers don't need to instantiate manually
local _instance: any
local _autoUnlockEnabled = true -- default on; can be toggled by user preferences later

local function getOrCreate()
	if _instance then
		return _instance
	end
	_instance = SystemPanelHandler.new()
	return _instance
end

return {
	-- expose class constructor just in case
	new = SystemPanelHandler.new,
	get = getOrCreate,
	-- preference flag API
	isAutoUnlockEnabled = function(): boolean
		return _autoUnlockEnabled
	end,
	setAutoUnlockEnabled = function(v: boolean)
		_autoUnlockEnabled = v and true or false
	end,
	show = function()
		local inst = getOrCreate()
		inst:displayPanel()
		if _autoUnlockEnabled then
			-- Auto-unlock cursor for OS interaction
			local CameraController = require(script.Parent.Parent.Parent.CameraController)
			CameraController.getInstance():setCursorUnlocked(true)
		end
	end,
	hide = function()
		local inst = getOrCreate()
		inst:hidePanel()
		if _autoUnlockEnabled then
			-- Re-lock cursor when panel hides (in OS mode this resumes look)
			local CameraController = require(script.Parent.Parent.Parent.CameraController)
			CameraController.getInstance():setCursorUnlocked(false)
		end
	end,
	toggle = function()
		local inst = getOrCreate()
		local worldGUIManager = WorldGUIManager.getInstance()
		local visible = worldGUIManager:isPanelVisible("SystemPanel")
		inst:togglePanel()
		local CameraController = require(script.Parent.Parent.Parent.CameraController)
		-- After toggling, query new state to decide lock/unlock
		local nowVisible = worldGUIManager:isPanelVisible("SystemPanel")
		if _autoUnlockEnabled then
			if nowVisible and not visible then
				CameraController.getInstance():setCursorUnlocked(true)
			elseif (not nowVisible) and visible then
				CameraController.getInstance():setCursorUnlocked(false)
			end
		end
	end,
	updateStats = function(s)
		getOrCreate():updateStats(s)
	end,
	updateAttributes = function(a)
		getOrCreate():updateAttributes(a)
	end,
	setMenuView = function(view: string)
		getOrCreate():setMenuView(view)
	end,
	cycleMenuView = function(direction: number?)
		getOrCreate():cycleMenuView(direction)
	end,
	toggleMenuView = function(view: string)
		local inst = getOrCreate()
		local wasOpen = inst._menuOpen
		inst:toggleMenuView(view)
		if _autoUnlockEnabled then
			local CameraController = require(script.Parent.Parent.Parent.CameraController)
			local isOpen = inst._menuOpen
			if isOpen ~= wasOpen then
				CameraController.getInstance():setCursorUnlocked(isOpen)
			end
		end
	end,
	isVisible = function(): boolean
		local inst = getOrCreate()
		return inst._menuOpen
	end,
}
