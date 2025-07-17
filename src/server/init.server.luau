-- Main server initialization script
print("Server starting...")

-- Initialize the stats management system
local _StatsManager = require(script.StatsManager)
local AttributesManager = require(script.AttributesManager)

-- Initialize the regeneration service
local RegenerationService = require(script.RegenerationService)
RegenerationService.start()

-- Example: Set up some demo commands (you can remove these later)
local Players = game:GetService("Players")
local Testing = require(script.Testing)

-- Example function to test the system
local function setupPlayerCommands(player: Player)
	-- Wait a bit for the player to load
	wait(6)

	-- Apply attribute scaling after stats and attributes are initialized
	AttributesManager.applyAllScaling(player)

	Testing.runAllTests(player)
end

-- Connect to new players for demo purposes
Players.PlayerAdded:Connect(function(player)
	spawn(function()
		setupPlayerCommands(player)
	end)
end)

-- Clean up tests when player leaves
Players.PlayerRemoving:Connect(function(player)
	Testing.stopTests(player)
end)

print("Server initialized with AttributesManager and Examples")
