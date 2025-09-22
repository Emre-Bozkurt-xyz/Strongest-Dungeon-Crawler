--!strict
-- Client-side system panel handler for displaying stats and attributes

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HealthBarController = require(script.Parent.HealthBarController)
local ManaBarController = require(script.Parent.ManaBarController)
local StaminaBarController = require(script.Parent.StaminaBarController)
local AttributesUIController = require(script.Parent.AttributesUIController)
local WorldGUIManager = require(script.Parent.WorldGUIManager)

local SystemPanelHandler = {}
SystemPanelHandler.__index = SystemPanelHandler

-- Import clients for centralized data access
local AttributesClient = require(script.Parent.AttributesClient)
local StatsClient = require(script.Parent.StatsClient)
local NetRay = require(ReplicatedStorage.Packages.NetRay)

function SystemPanelHandler.new()
	local self = setmetatable({}, SystemPanelHandler)

	-- Create the system panel
	self.systemPanel = ReplicatedStorage.Assets.SystemPanel:Clone()

	-- Initialize UI controllers
	local statusPanel = self.systemPanel:FindFirstChild("StatusPanel", true)
	local attributesPanel = self.systemPanel:FindFirstChild("AttributesPanel", true)
	if statusPanel and attributesPanel then
		self.staminaBarController = StaminaBarController.new(statusPanel)
		self.healthBarController = HealthBarController.new(statusPanel)
		self.manaBarController = ManaBarController.new(statusPanel)
		self.attributesUIController = AttributesUIController.new(attributesPanel)
	end

	-- Register panel with WorldGUIManager for positioning
	local worldGUIManager = WorldGUIManager.getInstance()
	worldGUIManager:registerPanel({
		name = "SystemPanel",
		part = self.systemPanel,
		faceCamera = true,
		followPlayer = true,
		followMode = "camera",
		offset = Vector3.new(0, 0.75, 0), -- lift the panel slightly to avoid player head overlap
		camSpaceOffset = Vector3.new(0, 0.0, 0.0), -- tweak if needed without affecting OS mode
	})

	-- Listen for stats updates via NetRay event
	local statsEvent = NetRay:GetEvent("StatsDelta")
	if statsEvent then
		statsEvent:OnEvent(function(_delta)
			-- Let StatsClient consume and update state first, then refresh UI
			task.defer(function()
				local statsData = StatsClient.getFormattedStats()
				if statsData then
					self:updateStats(statsData)
				end
			end)
		end)
	end

	-- Listen for attributes updates via NetRay event
	local attributesEvent = NetRay:GetEvent("AttributesDelta")
	if attributesEvent then
		attributesEvent:OnEvent(function(_delta)
			-- Pull latest state from AttributesClient and update UI
			task.defer(function()
				local attributeData = AttributesClient.getFormattedAttributes()
				if attributeData then
					self:updateAttributes(attributeData)
				end
			end)
		end)
	end

	-- Initial update to get current data
	local function initialUpdate()
		-- Update stats
		local statsData = StatsClient.getFormattedStats()
		if statsData then
			self:updateStats(statsData)
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
end

function SystemPanelHandler:updateAttributes(attributes)
	-- Logic to update attributes in the system panel
	if not self.attributesUIController then
		warn("Attributes UI Controller not initialized")
		return
	end

	self.attributesUIController:updateAttributes(attributes)
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
	worldGUIManager:setPanelVisibility("SystemPanel", true, 0.5, workspace)

	-- No focus effects; CameraController handles per-mode follow behavior
end

function SystemPanelHandler:hidePanel()
	-- Use WorldGUIManager for smooth hiding (it will handle unparenting after fade)
	local worldGUIManager = WorldGUIManager.getInstance()
	worldGUIManager:setPanelVisibility("SystemPanel", false, 0.5, workspace)

	-- No focus effects on hide
end

-- Lazy singleton facade so callers don't need to instantiate manually
local _instance: any

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
}
