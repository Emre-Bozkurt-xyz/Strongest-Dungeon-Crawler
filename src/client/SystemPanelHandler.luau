--!strict
-- Client-side system panel handler for displaying stats and attributes

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local warp = require(ReplicatedStorage.Packages.warp)
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)
local HealthBarController = require(script.Parent.HealthBarController)
local ManaBarController = require(script.Parent.ManaBarController)
local StaminaBarController = require(script.Parent.StaminaBarController)

local SystemPanelHandler = {}
SystemPanelHandler.__index = SystemPanelHandler

local statsReceivedSignal = warp.Signal("StatsReceived")

function SystemPanelHandler.new()
	local self = setmetatable({}, SystemPanelHandler)

	-- Initialize any properties or connections here
	self.systemPanel = ReplicatedStorage.Shared.SystemPanel:Clone()
	-- Example: Connect a button click event
	local statusPanel = self.systemPanel:FindFirstChild("StatusPanel", true)
	if statusPanel then
		self.staminaBarController = StaminaBarController.new(statusPanel)
		self.healthBarController = HealthBarController.new(statusPanel)
		self.manaBarController = ManaBarController.new(statusPanel)
	end

	statsReceivedSignal:Connect(function(newStats)
		self:updateStats(newStats)
	end)

	return self
end

function SystemPanelHandler:updateStats(newStats: StatTypes.PlayerStats)
	-- Logic to update stats in the system panel
	if not self.systemPanel then
		warn("System panel not initialized")
		return
	end

	self.healthBarController:updateHealth(newStats.Health:getCurrentValue(), newStats.Health:getValue())
	self.manaBarController:updateMana(newStats.Mana:getCurrentValue(), newStats.Mana:getValue())
	self.staminaBarController:updateStamina(newStats.Stamina:getCurrentValue(), newStats.Stamina:getValue())
end

function SystemPanelHandler:displayPanel()
	-- Logic to display stats in the system panel
	if not self.systemPanel then
		warn("System panel not initialized")
		return
	end
	if not self.systemPanel.Parent then
		self.systemPanel.Parent = workspace
	end
end

function SystemPanelHandler:hidePanel()
	-- Logic to hide the system panel
	if self.systemPanel and self.systemPanel.Parent then
		self.systemPanel.Parent = nil
	end
end

return SystemPanelHandler
