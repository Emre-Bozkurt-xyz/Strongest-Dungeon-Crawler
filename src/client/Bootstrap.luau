--!strict
-- Client Bootstrap: centralizes startup order and dev hooks.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local DebugConfig = require(ReplicatedStorage.Shared.Debug.DebugConfig)
local Diagnostics = require(ReplicatedStorage.Shared.BootstrapDiagnostics)

local Bootstrap = {}

type BootstrapContext = {
	isDev: boolean,
	SessionMirror: any?,
	Dev: any?,
}

local function startEntry(
	ctx: BootstrapContext,
	started: { [string]: boolean },
	name: string,
	fn: (BootstrapContext) -> any,
	requires: { string }?,
	devOnly: boolean?
)
	if devOnly and not ctx.isDev then
		return
	end
	if requires then
		for _, dep in ipairs(requires) do
			if not started[dep] then
				error(`Bootstrap: '{name}' requires '{dep}' which has not started`)
			end
		end
	end
	fn(ctx)
	started[name] = true
	Diagnostics.info(`Started {name}`)
end

function Bootstrap.startAll(): BootstrapContext
	local ctx: BootstrapContext = {
		isDev = DebugConfig.isDev(),
	}
	local started: { [string]: boolean } = {}

	Diagnostics.info("Starting client bootstrap")

	startEntry(ctx, started, "CoreServices", function(_context)
		local AssetLoader = require(script.Parent.AssetLoader)
		local TimeSync = require(script.Parent.Services.TimeSync)
		local Clock = require(ReplicatedStorage.Shared.Time.Clock)
		Diagnostics.assert(AssetLoader ~= nil, "AssetLoader failed to load")
		Diagnostics.assert(TimeSync ~= nil, "TimeSync failed to load")
		AssetLoader.init()
		TimeSync.start()
		Clock.setServerNowProvider(TimeSync.getServerNow)
	end)

	startEntry(ctx, started, "SessionMirror", function(context)
		local SessionMirror = require(script.Parent.SkillsFramework.SessionMirror)
		Diagnostics.assert(SessionMirror ~= nil, "SessionMirror failed to load")
		SessionMirror.initialize()
		context.SessionMirror = SessionMirror
	end, { "CoreServices" })

	startEntry(ctx, started, "Permissions", function(context)
		local ActionPermissions = require(ReplicatedStorage.Shared.ActionPermissions)
		Diagnostics.assert(ActionPermissions ~= nil, "ActionPermissions failed to load")
		ActionPermissions.client(context.SessionMirror)
	end, { "SessionMirror" })

	startEntry(ctx, started, "UIControllers", function(_context)
		local StatsClient = require(script.Parent.StatsClient)
		local AttributesClient = require(script.Parent.AttributesClient)
		local CameraController = require(script.Parent.CameraController)
		local InteractionStateController = require(script.Parent.input.InteractionStateController)
		local Inputs = require(script.Parent.Inputs)
		local StatusPreviewController = require(script.Parent.ui.controllers.StatusPreviewController)
		local SystemPanelRuntime = require(script.Parent.ui.runtime.SystemPanelRuntime)
		local MenuOrchestrator = require(script.Parent.ui.menu.MenuOrchestrator)
		local SkillSlotUI = require(script.Parent.SkillsFramework.SkillSlotUI)
		local InventoryClient = require(script.Parent.Inventory.InventoryClient)
		local OverheadHealthService = require(script.Parent.OverheadHealthService)
		local DamageNumberController = require(script.Parent.ui.DamageNumberController)
		local StaggerController = require(script.Parent.ui.controllers.StaggerController)
		local InventoryMenuRuntime = require(script.Parent.ui.runtime.InventoryMenuRuntime)
		local LootClient = require(script.Parent.ui.controllers.LootClient)
		Diagnostics.assert(StatsClient ~= nil, "StatsClient failed to load")
		Diagnostics.assert(AttributesClient ~= nil, "AttributesClient failed to load")
		Diagnostics.assert(CameraController ~= nil, "CameraController failed to load")
		Diagnostics.assert(SkillSlotUI ~= nil, "SkillSlotUI failed to load")
		InteractionStateController.init()
		Inputs.init()

		DamageNumberController.init()
		StaggerController.init()

		local player = Players.LocalPlayer

		local function onCharacterAdded(_character: Model)
			task.wait(1)
			StatsClient.requestStatsUpdate()
			AttributesClient.requestAttributesData()
			InventoryClient.requestSnapshot()

			-- Pull the authoritative skill list. Server-side `skill_added` deltas are fired when
			-- the character registers, which is typically before SkillsClient has subscribed, so
			-- without this catch-up the client can end up with no usable skills and no error.
			local SkillsClient = require(script.Parent.SkillsFramework.SkillsClient)
			SkillsClient.requestSnapshot()

			local SkillMetadataClient = require(script.Parent.SkillsFramework.SkillMetadataClient)
			SkillMetadataClient.requestSnapshot()

			MenuOrchestrator.init()
			SystemPanelRuntime.get()

			local cam = CameraController.getInstance()
			cam:setZoomLimits(2.5, 16)
			cam:enable()
			InteractionStateController.setCameraMode(cam.mode)

			StatusPreviewController.get()
			LootClient.init()

			local playerGui = player:WaitForChild("PlayerGui")
			local hud = playerGui:WaitForChild("HUD")
			local anchor = hud:FindFirstChild("SkillSlots")
			SkillSlotUI.mount(anchor)

			-- Only initialize inventory UI if templates exist (world-space panels).
			InventoryMenuRuntime.tryInit()
		end

		if player.Character then
			onCharacterAdded(player.Character)
		end
		player.CharacterAdded:Connect(onCharacterAdded)

		UserInputService.InputBegan:Connect(function(input, gpe)
			if gpe then
				return
			end
			if input.KeyCode == Enum.KeyCode.V then
				local cam = CameraController.getInstance()
				cam:toggleMode()
			end
		end)

		OverheadHealthService.start()
	end, { "SessionMirror" })

	startEntry(ctx, started, "DevHooks", function(context)
		local dev = require(script.Parent.dev.InitDev)
		dev.start(context)
		context.Dev = dev
	end, nil, true)

	Diagnostics.info("Client bootstrap complete")
	return ctx
end

return Bootstrap
