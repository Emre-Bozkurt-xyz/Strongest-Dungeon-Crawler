-- Main client initialization script
print("Client starting...")

-- Initialize the attributes client system
local StatsClient = require(script.StatsClient)

-- Example: Add some client-side commands for testing
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local _player = Players.LocalPlayer

local statsClient = StatsClient.new()

statsClient:displayStats()

print("Client initialized")
