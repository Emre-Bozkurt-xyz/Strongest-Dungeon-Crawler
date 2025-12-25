-- Main client initialization script
print("Client starting...")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local AssetLoader = require(script.AssetLoader)

AssetLoader.init()

-- Initialize SessionMirror first so permission checks can use session state
local SessionMirror = require(script.SkillsFramework.SessionMirror)
SessionMirror.initialize()

local ENABLE_SESSION_PERF_TIMER = false
local SESSION_PERF_INTERVAL = 15

-- Initialize the client systems (they auto-initialize when required)
local ActionPermissions = require(ReplicatedStorage.Shared.ActionPermissions)
ActionPermissions.client(SessionMirror) -- Initialize to listen for blocking events

local StatsClient = require(script.StatsClient)
local AttributesClient = require(script.AttributesClient)
local CameraController = require(script.CameraController)
local StatusPreviewController = require(script.ui.controllers.StatusPreviewController)
local SystemPanelHandler = require(script.ui.controllers.SystemPanelHandler)
local SkillSlotUI = require(script.SkillsFramework.SkillSlotUI)
local OverheadHealthService = require(script.OverheadHealthService)
local DamageNumberController = require(script.ui.DamageNumberController)
DamageNumberController.init()
local StaggerController = require(script.ui.controllers.StaggerController)
StaggerController.init()

if ENABLE_SESSION_PERF_TIMER then
	task.spawn(function()
		SessionMirror.resetPerfStats()
		while true do
			task.wait(SESSION_PERF_INTERVAL)
			local stats = SessionMirror.getPerfStats()
			print(`[SessionPerf] Client {HttpService:JSONEncode(stats)}`)
			SessionMirror.resetPerfStats()
		end
	end)
end

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
end

-- Wait for character to spawn
local function onCharacterAdded(_character: Model)
	-- Wait a moment for character to fully load
	task.wait(1)

	-- Set up first-person camera
	--_setupFirstPersonCamera()

	-- Request initial data from server
	StatsClient.requestStatsUpdate()
	AttributesClient.requestAttributesData()

	-- Request skill metadata snapshot
	local SkillMetadataClient = require(script.SkillsFramework.SkillMetadataClient)
	SkillMetadataClient.requestSnapshot()

	-- Ensure SystemPanelHandler is initialized so it listens for StatsDelta/AttributesDelta
	SystemPanelHandler.get()

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

-- Start overhead HP bars service
OverheadHealthService.start()

-- Phase 2: SessionMirror already initialized above
