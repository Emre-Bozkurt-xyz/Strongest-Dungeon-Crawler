-- Main client initialization script
print("Client starting...")

-- Initialize the attributes client system
local StatsClient = require(script.StatsClient)
local _ClientTesting = require(script.ClientTesting) -- Auto-starts monitoring

-- Example: Add some client-side commands for testing
local Players = game:GetService("Players")

local _player = Players.LocalPlayer

local statsClient = StatsClient.new()

-- Request initial stats from server
statsClient:requestStatsUpdate()

statsClient:displayStats()

-- Start client-side testing (monitoring is already auto-started)
print("📊 Client testing initialized")

print("Client initialized")
