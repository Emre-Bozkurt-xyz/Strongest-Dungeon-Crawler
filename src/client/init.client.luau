-- Main client initialization script
print("Client starting...")

-- Initialize the client systems (they auto-initialize when required)
local StatsClient = require(script.StatsClient)
local AttributesClient = require(script.AttributesClient)
local CameraController = require(script.CameraController)
local StatusPreviewController = require(script.ui.controllers.StatusPreviewController)
local SkillSlotUI = require(script.SkillsFramework.SkillSlotUI)
local UserInputService = game:GetService("UserInputService")

-- Example: Add some client-side commands for testing
local Players = game:GetService("Players")
local _player = Players.LocalPlayer

-- Debug Controls (set to false to reduce console spam)
local function _setGUIDebug(enabled: boolean)
	-- We can add debug controls here later if needed
	print(`🐛 GUI debug mode: {enabled and "ON" or "OFF"}`)
end

-- Example: Uncomment to disable GUI debug logging
-- _setGUIDebug(false)

-- Set camera to first person
local function _setupFirstPersonCamera()
	_player.CameraMode = Enum.CameraMode.LockFirstPerson
	print("📷 First-person camera enabled")
end

-- Wait for character to spawn
local function onCharacterAdded(character: Model)
	-- Wait a moment for character to fully load
	task.wait(1)

	print(`📷 Setting up first-person camera and GUI for {character.Name}`)

	-- Set up first-person camera
	--_setupFirstPersonCamera()

	-- Request initial data from server
	StatsClient.requestStatsUpdate()
	AttributesClient.requestAttributesData()

	-- Initialize/refresh camera controller on spawn
	local cam = CameraController.getInstance()
	cam:setZoomLimits(2.5, 16)
	cam:enable()

	-- Ensure the status preview is created and visible
	StatusPreviewController.get()

	-- Mount skill slot UI (only once)
	local playerGui = _player:WaitForChild("PlayerGui")
	local hud = playerGui:WaitForChild("HUD")
	local anchor = hud:FindFirstChild("SkillSlots")
	SkillSlotUI.mount(anchor)

	print("📷 First-person camera and world GUI systems initialized")
end

-- Handle character spawning/respawning
if _player.Character then
	onCharacterAdded(_player.Character)
end
_player.CharacterAdded:Connect(onCharacterAdded)

-- Bind a toggle for camera mode (V)
UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then
		return
	end
	if input.KeyCode == Enum.KeyCode.V then
		local cam = CameraController.getInstance()
		cam:toggleMode()
	end
end)

-- Start client-side testing (monitoring is already auto-started)
print("📊 Client testing initialized")

print("Client initialized")

local CooldownClient = require(script.SkillsFramework.CooldownClient)
CooldownClient.onChanged(function(evt, key)
    if key == "_GCD" then
        local rec = CooldownClient.get("_GCD")
        print("[GCD EVENT]", evt, rec and (rec.endAt - os.clock()) or "cleared")
    end
end)