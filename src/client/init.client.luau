-- Main client initialization script
print("Client starting...")

-- Initialize the attributes client system
local AttributesClient = require(script.AttributesClient)
local SystemPanelHandler = require(script.SystemPanelHandler)

-- Example: Add some client-side commands for testing
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local _player = Players.LocalPlayer

-- Initialize the system panel handler
local systemPanelHandler = SystemPanelHandler.new()

-- Example keyboard shortcuts for testing (you can remove these later)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.KeyCode == Enum.KeyCode.F1 then
		-- Request attributes update
		AttributesClient.requestAttributesUpdate()
		print("Requested attributes update")
	elseif input.KeyCode == Enum.KeyCode.F2 then
		-- Print current attributes to console
		local attributes = AttributesClient.getCurrentAttributes()
		if attributes then
			print("Current Attributes:")
			for attributeName, attributeData in pairs(attributes) do
				print(
					`  {attributeName}: {attributeData.current} (Base: {attributeData.base}, Bonus: {attributeData.bonus})`
				)
			end
		else
			print("No attributes available")
		end
	end
end)

print("Client initialized with AttributesClient")
