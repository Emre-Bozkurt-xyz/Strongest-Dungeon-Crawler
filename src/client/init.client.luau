-- Main client initialization script
print("Client starting...")

-- Initialize the client systems (they auto-initialize when required)
local StatsClient = require(script.StatsClient)
local AttributesClient = require(script.AttributesClient)
--local _ClientTesting = require(script.ClientTesting) -- Auto-starts monitoring

-- Initialize world GUI system (no more camera controller needed)
local WorldGUIManager = require(script.WorldGUIManager)
local SystemPanelHandler = require(script.SystemPanelHandler)

-- Example: Add some client-side commands for testing
local Players = game:GetService("Players")
local _player = Players.LocalPlayer

-- Debug Controls (set to false to reduce console spam)
local function setGUIDebug(enabled: boolean)
	-- We can add debug controls here later if needed
	print(`🐛 GUI debug mode: {enabled and "ON" or "OFF"}`)
end

-- Example: Uncomment to disable GUI debug logging
-- setGUIDebug(false)

-- Set camera to first person
local function setupFirstPersonCamera()
	_player.CameraMode = Enum.CameraMode.LockFirstPerson
	print("📷 First-person camera enabled")
end

-- Wait for character to spawn
local function onCharacterAdded(character: Model)
	-- Wait a moment for character to fully load
	task.wait(1)

	print(`📷 Setting up first-person camera and GUI for {character.Name}`)

	-- Set up first-person camera
	--setupFirstPersonCamera()

	-- Initialize world GUI system
	local _worldGUIManager = WorldGUIManager.getInstance()

	-- Request initial data from server
	StatsClient.requestStatsUpdate()
	AttributesClient.requestAttributesData()

	-- Create and display system panel (it will auto-register with WorldGUIManager)
	local systemPanelHandler = SystemPanelHandler.new()
	--systemPanelHandler:displayPanel()

	print("📷 First-person camera and world GUI systems initialized")
end

-- Handle character spawning/respawning
if _player.Character then
	onCharacterAdded(_player.Character)
end
_player.CharacterAdded:Connect(onCharacterAdded)

-- Start client-side testing (monitoring is already auto-started)
print("📊 Client testing initialized")

print("Client initialized")
