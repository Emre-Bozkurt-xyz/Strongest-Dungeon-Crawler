--!strict
-- SystemPanelRuntime: world-space system panel runtime for stats, attributes, and menu camera behavior.

local HealthBarController = require(script.Parent.Parent.controllers.HealthBarController)
local ManaBarController = require(script.Parent.Parent.controllers.ManaBarController)
local StaminaBarController = require(script.Parent.Parent.controllers.StaminaBarController)
local AttributesUIController = require(script.Parent.Parent.controllers.AttributesUIController)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local WorldGUIManager = require(script.Parent.Parent.Parent.WorldGUIManager)
local MenuRigRuntime = require(script.Parent.Parent.menu.MenuRigRuntime)
local StatusPreviewController = require(script.Parent.Parent.controllers.StatusPreviewController)
local PanelTemplateResolver = require(script.Parent.PanelTemplateResolver)
local PanelBinder = require(script.Parent.PanelBinder)
local Config = require(ReplicatedStorage.Shared.Config)
local DevTuningService = require(script.Parent.Parent.Parent.dev.DevTuningService)

local SystemPanelRuntime = {}
SystemPanelRuntime.__index = SystemPanelRuntime

local UIMenuConfig = Config.UIMenu
local CameraConfig = Config.Camera
local MENU_GROUP_NAME = UIMenuConfig.groupName
local MENU_GROUP_PARAMS = UIMenuConfig.groupParams
local MENU_SYSTEM_BOOTSTRAP_WEIGHTS = UIMenuConfig.centerWeights.systemPanelBootstrap
local SYSTEM_PANEL_CONFIG = UIMenuConfig.panels.SystemPanel
local SYSTEM_PANEL_RADIUS_PADDING_FLOOR = UIMenuConfig.systemPanel.radiusPaddingFloor
local SYSTEM_MENU_CAMERA_MODIFIER = CameraConfig.modifiers.systemMenuFocus

local function tunedString(path: string, fallback: string): string
	local value = DevTuningService.get(path)
	return if type(value) == "string" then value else fallback
end

local function tunedNumber(path: string, fallback: number): number
	local value = DevTuningService.get(path)
	return if type(value) == "number" then value else fallback
end

local function tunedVector3(path: string, fallback: Vector3): Vector3
	local value = DevTuningService.get(path)
	return if typeof(value) == "Vector3" then value else fallback
end

local function tunedTable(path: string, fallback: { [string]: any }): { [string]: any }
	local value = DevTuningService.get(path)
	return if type(value) == "table" then value else fallback
end

local function applyUIMenuTuning()
	MENU_GROUP_NAME = tunedString("UIMenu.groupName", UIMenuConfig.groupName)
	MENU_GROUP_PARAMS = tunedTable("UIMenu.groupParams", UIMenuConfig.groupParams)
	MENU_SYSTEM_BOOTSTRAP_WEIGHTS = tunedTable(
		"UIMenu.centerWeights.systemPanelBootstrap",
		UIMenuConfig.centerWeights.systemPanelBootstrap
	)
	SYSTEM_PANEL_CONFIG = tunedTable("UIMenu.panels.SystemPanel", UIMenuConfig.panels.SystemPanel)
	SYSTEM_PANEL_RADIUS_PADDING_FLOOR = tunedNumber(
		"UIMenu.systemPanel.radiusPaddingFloor",
		UIMenuConfig.systemPanel.radiusPaddingFloor
	)
end

applyUIMenuTuning()

-- Import clients for centralized data access
local AttributesClient = require(script.Parent.Parent.Parent.AttributesClient)
local StatsClient = require(script.Parent.Parent.Parent.StatsClient)

local function resolvePanelTemplate(name: string): BasePart
	local template = PanelTemplateResolver.resolveWorldPart(name)
	assert(template, `SystemPanelRuntime: missing panel template {name}`)
	return template
end

local function cloneSystemMenuCameraModifier()
	local tuned = DevTuningService.get("Camera.modifiers.systemMenuFocus")
	local source = if type(tuned) == "table" then tuned else SYSTEM_MENU_CAMERA_MODIFIER
	local modifier = table.clone(source)
	if modifier.yawAssist then
		modifier.yawAssist = table.clone(modifier.yawAssist)
	end
	if modifier.lookTarget then
		modifier.lookTarget = table.clone(modifier.lookTarget)
	end
	return modifier
end

local function applyMenuCameraPose(cam, cameraModifier)
	local rig = MenuRigRuntime.get()
	local basisYaw = rig:getBasisYaw()
	if type(basisYaw) ~= "number" then
		return
	end

	local entryPose = cameraModifier.entryPose
	local yawOffset = 0
	local pitch = nil
	if type(entryPose) == "table" then
		if type(entryPose.yawOffset) == "number" then
			yawOffset = entryPose.yawOffset
		end
		if type(entryPose.pitch) == "number" then
			pitch = entryPose.pitch
		end
	end

	cam:setAngles(basisYaw + yawOffset, pitch)
end

function SystemPanelRuntime:_reapplyCameraModifier()
	if not self._menuOpen then
		return
	end
	local CameraController = require(script.Parent.Parent.Parent.CameraController)
	local cam = CameraController.getInstance()
	if self._cameraModId then
		cam:popModifier(self._cameraModId)
	end
	local cameraModifier = cloneSystemMenuCameraModifier()
	applyMenuCameraPose(cam, cameraModifier)
	cameraModifier.lookAtProvider = function()
		return MenuRigRuntime.get():getFocusPoint()
	end
	self._cameraModId = cam:pushModifier(cameraModifier)
end

function SystemPanelRuntime:_applyUIMenuTuningToRuntime()
	if not self.systemPanel then
		return
	end

	local radiusPadding = SYSTEM_PANEL_RADIUS_PADDING_FLOOR
	if self.systemPanel:IsA("BasePart") then
		radiusPadding = math.max(radiusPadding, self.systemPanel.Size.Z * 0.5)
	end

	local worldGUIManager = WorldGUIManager.getInstance()
	worldGUIManager:setGroupParams(MENU_GROUP_NAME, {
		lerpSpeed = tunedNumber("UIMenu.groupParams.lerpSpeed", UIMenuConfig.groupParams.lerpSpeed),
		minRadius = tunedNumber("UIMenu.groupParams.minRadius", UIMenuConfig.groupParams.minRadius),
		maxRadius = tunedNumber("UIMenu.groupParams.maxRadius", UIMenuConfig.groupParams.maxRadius),
		radiusPadding = radiusPadding,
		playerOffsetMode = tunedString("UIMenu.panels.SystemPanel.playerOffsetMode", UIMenuConfig.panels.SystemPanel.playerOffsetMode),
		centerWeights = tunedTable("UIMenu.centerWeights.systemPanelBootstrap", UIMenuConfig.centerWeights.systemPanelBootstrap),
	})

	worldGUIManager:updatePanel("SystemPanel", {
		group = MENU_GROUP_NAME,
		offset = tunedVector3("UIMenu.panels.SystemPanel.offset", UIMenuConfig.panels.SystemPanel.offset),
		playerSpaceOffset = tunedVector3(
			"UIMenu.panels.SystemPanel.playerSpaceOffset",
			UIMenuConfig.panels.SystemPanel.playerSpaceOffset
		),
		faceBlend = tunedNumber("UIMenu.panels.SystemPanel.faceBlend", UIMenuConfig.panels.SystemPanel.faceBlend),
		playerOffsetMode = tunedString(
			"UIMenu.panels.SystemPanel.playerOffsetMode",
			UIMenuConfig.panels.SystemPanel.playerOffsetMode
		),
		maxRadius = tunedNumber("UIMenu.panels.SystemPanel.maxRadius", UIMenuConfig.panels.SystemPanel.maxRadius),
	})
end

function SystemPanelRuntime.new()
	local self = setmetatable({}, SystemPanelRuntime)

	-- Create the system panel
	self.systemPanel = resolvePanelTemplate("SystemPanel"):Clone()
	local radiusPadding = SYSTEM_PANEL_RADIUS_PADDING_FLOOR
	if self.systemPanel and self.systemPanel:IsA("BasePart") then
		radiusPadding = math.max(radiusPadding, self.systemPanel.Size.Z * 0.5)
	end

	-- Initialize UI controllers
	local binder = PanelBinder.new(self.systemPanel)
	self.statusPanel = binder:require({ "StatusPanel" }, "Frame", "SystemPanel.StatusPanel")
	self.attributesPanel = binder:require({ "AttributesPanel" }, "Frame", "SystemPanel.AttributesPanel")
	self.infoPanel = binder:find({ "InfoPanel" }, "Frame")
	if self.statusPanel and self.attributesPanel then
		self.staminaBarController = StaminaBarController.new(self.statusPanel)
		self.healthBarController = HealthBarController.new(self.statusPanel)
		self.manaBarController = ManaBarController.new(self.statusPanel)
		self.attributesUIController = AttributesUIController.new(self.attributesPanel)
	end

	-- Register panel with WorldGUIManager for positioning
	local worldGUIManager = WorldGUIManager.getInstance()
	worldGUIManager:setGroupParams(MENU_GROUP_NAME, {
		lerpSpeed = MENU_GROUP_PARAMS.lerpSpeed,
		minRadius = MENU_GROUP_PARAMS.minRadius,
		maxRadius = MENU_GROUP_PARAMS.maxRadius,
		radiusPadding = radiusPadding,
		playerOffsetMode = SYSTEM_PANEL_CONFIG.playerOffsetMode,
		centerWeights = MENU_SYSTEM_BOOTSTRAP_WEIGHTS,
	})
	worldGUIManager:registerPanel({
		name = "SystemPanel",
		part = self.systemPanel,
		group = MENU_GROUP_NAME,
		faceCamera = true,
		faceMode = "playerYaw",
		faceBlend = SYSTEM_PANEL_CONFIG.faceBlend,
		followMode = "player",
		offset = SYSTEM_PANEL_CONFIG.offset,
		playerSpaceOffset = SYSTEM_PANEL_CONFIG.playerSpaceOffset,
		playerOffsetMode = SYSTEM_PANEL_CONFIG.playerOffsetMode,
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
	self._tuneConnUIMenu = DevTuningService.subscribe("UIMenu", function()
		applyUIMenuTuning()
		self:_applyUIMenuTuningToRuntime()
	end)
	self._tuneConn = DevTuningService.subscribe("Camera.modifiers.systemMenuFocus", function()
		self:_reapplyCameraModifier()
	end)
	self:_applyUIMenuTuningToRuntime()

	return self
end

function SystemPanelRuntime:updateStats(newStats)
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

function SystemPanelRuntime:updateAttributes(attributes)
	-- Logic to update attributes in the system panel
	if not self.attributesUIController then
		warn("Attributes UI Controller not initialized")
		return
	end

	self.attributesUIController:updateAttributes(attributes)
end

function SystemPanelRuntime:setMenuView(view: string)
	self._menuView = view
	local worldGUIManager = WorldGUIManager.getInstance()
	if self._menuOpen then
		local showSystem = view == "system"
		if showSystem then
			-- Re-apply tuned placement whenever system view becomes primary.
			self:_applyUIMenuTuningToRuntime()
		end
		worldGUIManager:setPanelVisibility("SystemPanel", showSystem, 0.2, workspace)
	end
end

function SystemPanelRuntime:cycleMenuView(direction: number?)
	local worldGUIManager = WorldGUIManager.getInstance()
	if not worldGUIManager:isPanelVisible("SystemPanel") then
		return
	end
	local views = { "system", "inventory", "equipment" }
	local idx = 1
	for i, view in ipairs(views) do
		if view == self._menuView then
			idx = i
			break
		end
	end
	local dir = if (direction or 1) >= 0 then 1 else -1
	local nextIdx = idx + dir
	if nextIdx < 1 then
		nextIdx = #views
	elseif nextIdx > #views then
		nextIdx = 1
	end
	self:setMenuView(views[nextIdx])
end

function SystemPanelRuntime:togglePanel()
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

function SystemPanelRuntime:displayPanel()
	-- WorldGUIManager handles positioning, we just need to place it in workspace
	if not self.systemPanel then
		warn("System panel not initialized")
		return
	end

	-- Use WorldGUIManager visibility controls (it will handle parenting)
	local worldGUIManager = WorldGUIManager.getInstance()
	worldGUIManager:setPanelFollowMode("SystemPanel", "player")
	worldGUIManager:setPanelFollowModeLock("SystemPanel", true)
	worldGUIManager:setPanelPlayerSpaceOffset(
		"SystemPanel",
		tunedVector3("UIMenu.panels.SystemPanel.playerSpaceOffset", UIMenuConfig.panels.SystemPanel.playerSpaceOffset)
	)
	self._menuOpen = true

	-- Hide status preview while system panel is shown
	worldGUIManager:setPanelVisibility("StatusPreview", false, 0.2, workspace)
	self:setMenuView(self._menuView)

	local CameraController = require(script.Parent.Parent.Parent.CameraController)
	local cam = CameraController.getInstance()
	cam:clearFocus()
	if self._cameraModId then
		cam:popModifier(self._cameraModId)
		self._cameraModId = nil
	end
	local cameraModifier = cloneSystemMenuCameraModifier()
	applyMenuCameraPose(cam, cameraModifier)
	cameraModifier.lookAtProvider = function()
		return MenuRigRuntime.get():getFocusPoint()
	end
	self._cameraModId = cam:pushModifier(cameraModifier)
end

function SystemPanelRuntime:hidePanel()
	-- Use WorldGUIManager for smooth hiding (it will handle unparenting after fade)
	local worldGUIManager = WorldGUIManager.getInstance()
	self._menuOpen = false
	worldGUIManager:setPanelFollowModeLock("SystemPanel", false)
	worldGUIManager:setPanelFollowMode("SystemPanel", "camera")
	worldGUIManager:setPanelVisibility("SystemPanel", false, 0.5, workspace)

	-- Show status preview again
	worldGUIManager:setPanelVisibility("StatusPreview", true, 0.2, workspace)

	local CameraController = require(script.Parent.Parent.Parent.CameraController)
	local cam = CameraController.getInstance()
	cam:clearFocus()
	if self._cameraModId then
		cam:popModifier(self._cameraModId)
		self._cameraModId = nil
	end
end

function SystemPanelRuntime:toggleMenuView(view: string)
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

function SystemPanelRuntime:togglePreview()
	-- Temporarily hide attribute and info panels to show only status bars
	if not self.attributesPanel or not self.infoPanel then
		warn("Attributes or Info panel not initialized")
		return
	end
	local currentlyVisible = self.attributesPanel.Visible or self.infoPanel.Visible
	self.attributesPanel.Visible = not currentlyVisible
	self.infoPanel.Visible = not currentlyVisible
end

function SystemPanelRuntime:destroy()
	if self._statsConn then
		self._statsConn:Disconnect()
		self._statsConn = nil
	end
	if self._attrConn then
		self._attrConn()
		self._attrConn = nil
	end
	if self._tuneConn then
		self._tuneConn()
		self._tuneConn = nil
	end
	if self._tuneConnUIMenu then
		self._tuneConnUIMenu()
		self._tuneConnUIMenu = nil
	end
	if self._cameraModId then
		local CameraController = require(script.Parent.Parent.Parent.CameraController)
		CameraController.getInstance():popModifier(self._cameraModId)
		self._cameraModId = nil
	end
	if self.systemPanel then
		self.systemPanel:Destroy()
		self.systemPanel = nil
	end
end

-- Lazy singleton facade so callers don't need to instantiate manually
local _instance: any

local function getOrCreate()
	if _instance then
		return _instance
	end
	_instance = SystemPanelRuntime.new()
	return _instance
end

return {
	-- expose class constructor just in case
	new = SystemPanelRuntime.new,
	get = getOrCreate,
	show = function()
		getOrCreate():displayPanel()
	end,
	hide = function()
		getOrCreate():hidePanel()
	end,
	toggle = function()
		getOrCreate():togglePanel()
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
		getOrCreate():toggleMenuView(view)
	end,
	isVisible = function(): boolean
		local inst = getOrCreate()
		return inst._menuOpen
	end,
	destroy = function()
		if _instance then
			_instance:destroy()
			_instance = nil
		end
	end,
}
