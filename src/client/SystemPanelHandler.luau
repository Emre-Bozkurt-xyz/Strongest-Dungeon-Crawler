local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HealthBarController = require(script.Parent.HealthBarController)
local ManaBarController = require(script.Parent.ManaBarController)
local StaminaBarController = require(script.Parent.StaminaBarController)

local SystemPanelHandler = {}
SystemPanelHandler.__index = SystemPanelHandler

function SystemPanelHandler.new()
	local self = setmetatable({}, SystemPanelHandler)

	-- Initialize any properties or connections here
	self.systemPanel = ReplicatedStorage.Shared.SystemPanel:Clone()
	self.systemPanel.Parent = workspace
	print("SystemPanelHandler initialized")
	-- Example: Connect a button click event
	local statusPanel = self.systemPanel:FindFirstChild("StatusPanel", true)
	if statusPanel then
		local staminaBarController = StaminaBarController.new(statusPanel)
		local healthBarController = HealthBarController.new(statusPanel)
		local manaBarController = ManaBarController.new(statusPanel)
	end

	return self
end

return SystemPanelHandler
