-- Main server initialization script
print("Server starting...")

-- Initialize the stats management system
local _StatsManager = require(script.StatsManager)
local _AttributesManager = require(script.AttributesManager)

-- Example: Set up some demo commands (you can remove these later)
local Players = game:GetService("Players")
local Testing = require(script.Testing)

-- Example function to test the system
local function setupPlayerCommands(player: Player)
	-- Wait a bit for the player to load
	wait(6)

	Testing.runAllTests(player)
end

-- Connect to new players for demo purposes
Players.PlayerAdded:Connect(function(player)
	spawn(function()
		setupPlayerCommands(player)
	end)
end)

print("Server initialized with AttributesManager and Examples")
