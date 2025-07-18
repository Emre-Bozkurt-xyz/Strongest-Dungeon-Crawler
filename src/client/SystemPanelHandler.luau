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
	})

	-- Listen for updates from the centralized system via signals instead of polling
	local warp = require(game.ReplicatedStorage.Packages.warp)

	-- Listen for stats updates
	local statsUpdatedSignal = warp.Signal("statsUpdated")
	statsUpdatedSignal:Connect(function(statsData)
		if statsData then
			self:updateStats(statsData)
		end
	end)

	-- Listen for attributes updates
	local attributesUpdatedSignal = warp.Signal("attributesUpdated")
	attributesUpdatedSignal:Connect(function(_attributesData)
		-- Don't use the signal parameter, get fresh formatted data instead
		local attributeData = AttributesClient.getFormattedAttributes()
		if attributeData then
			self:updateAttributes(attributeData)
		end
	end)

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

function SystemPanelHandler:displayPanel()
	-- WorldGUIManager handles positioning, we just need to place it in workspace
	if not self.systemPanel then
		warn("System panel not initialized")
		return
	end
	if not self.systemPanel.Parent then
		self.systemPanel.Parent = workspace
	end

	-- Optionally use WorldGUIManager visibility controls
	local worldGUIManager = WorldGUIManager.getInstance()
	worldGUIManager:setPanelVisibility("SystemPanel", true, 0.5)
end

function SystemPanelHandler:hidePanel()
	-- Use WorldGUIManager for smooth hiding
	local worldGUIManager = WorldGUIManager.getInstance()
	worldGUIManager:setPanelVisibility("SystemPanel", false, 0.5)

	-- After animation, remove from workspace
	task.wait(0.6) -- Wait for animation to complete
	if self.systemPanel and self.systemPanel.Parent then
		self.systemPanel.Parent = nil
	end
end

return SystemPanelHandler
