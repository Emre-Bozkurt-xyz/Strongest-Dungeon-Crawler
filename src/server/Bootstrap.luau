--!strict
-- Server Bootstrap: centralizes startup order and dev hooks.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugConfig = require(ReplicatedStorage.Shared.Debug.DebugConfig)
local Diagnostics = require(ReplicatedStorage.Shared.BootstrapDiagnostics)

local Bootstrap = {}

type BootstrapContext = {
	isDev: boolean,
	Registrar: any?,
	StatsManager: any?,
	AttributesManager: any?,
	InventoryService: any?,
	SessionManager: any?,
	SkillsManager: any?,
	SkillMetadataService: any?,
	SkillModifierRegistry: any?,
	StatusEffectsService: any?,
	CombatService: any?,
	NPCManager: any?,
	ComponentManager: any?,
	NPCSpawner: any?,
	EntityInfoService: any?,
	TimeSyncService: any?,
	StaggerSystem: any?,
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

	Diagnostics.info("Starting server bootstrap")

	startEntry(ctx, started, "Registrar", function(context)
		context.Registrar = require(script.Parent.Services.Registrar)
	end)

	startEntry(ctx, started, "Stats", function(context)
		context.StatsManager = require(script.Parent.Stats.StatsManager)
		context.AttributesManager = require(script.Parent.Stats.AttributesManager)
		Diagnostics.assert(context.StatsManager ~= nil, "StatsManager failed to load")
		Diagnostics.assert(context.AttributesManager ~= nil, "AttributesManager failed to load")
	end)

	startEntry(ctx, started, "RegenerationService", function(context)
		local svc = require(script.Parent.Services.RegenerationService)
		svc.start()
		context.RegenerationService = svc
	end, { "Stats" })

	startEntry(ctx, started, "InventoryService", function(context)
		context.InventoryService = require(script.Parent.Inventory.InventoryService)
		Diagnostics.assert(context.InventoryService ~= nil, "InventoryService failed to load")
	end, { "Registrar" })

	startEntry(ctx, started, "EquipmentVisuals", function(_context)
		local visuals = require(script.Parent.Inventory.EquipmentVisualService)
		Diagnostics.assert(visuals ~= nil, "EquipmentVisualService failed to load")
		visuals.start()
	end, { "InventoryService" })

	startEntry(ctx, started, "SkillsFramework", function(context)
		context.SessionManager = require(script.Parent.SkillsFramework.SessionManager)
		context.SkillsManager = require(script.Parent.SkillsFramework.SkillsManager)
		context.SkillMetadataService = require(script.Parent.SkillsFramework.SkillMetadataService)
		context.SkillModifierRegistry = require(script.Parent.Stats.SkillModifierRegistry)
		Diagnostics.assert(context.SessionManager ~= nil, "SessionManager failed to load")
	end, { "Registrar", "Stats" })

	startEntry(ctx, started, "CombatAndStatus", function(context)
		context.StatusEffectsService = require(script.Parent.StatusEffects.StatusEffectsService)
		context.CombatService = require(script.Parent.Services.CombatService)
		Diagnostics.assert(context.StatusEffectsService ~= nil, "StatusEffectsService failed to load")
		Diagnostics.assert(context.CombatService ~= nil, "CombatService failed to load")
		context.StatusEffectsService.setContext({
			applyAttack = function(targetEntityId: string, attack: any, sourceEntityId: string)
				context.CombatService.applyAttack(targetEntityId, attack, sourceEntityId)
			end,
		})
	end, { "SkillsFramework" })

	startEntry(ctx, started, "ProjectileRPC", function(_context)
		require(script.Parent.Services.ProjectileRPC)
	end, { "SkillsFramework" })

	startEntry(ctx, started, "NPCSystem", function(context)
		context.NPCManager = require(script.Parent.NPCService.NPCManager)
		context.ComponentManager = require(script.Parent.NPCService.ComponentManager)
		context.NPCSpawner = require(script.Parent.NPCService.NPCSpawner)
		Diagnostics.assert(context.NPCManager ~= nil, "NPCManager failed to load")
		context.NPCManager.initialize()
		RunService.Heartbeat:Connect(function(dt)
			context.ComponentManager.updateAll(dt)
		end)
	end, { "Registrar" })

	startEntry(ctx, started, "EntityInfoService", function(context)
		context.EntityInfoService = require(script.Parent.Services.EntityInfoService)
		Diagnostics.assert(context.EntityInfoService ~= nil, "EntityInfoService failed to load")
		context.EntityInfoService.start()
	end, { "Stats", "Registrar" })

	startEntry(ctx, started, "TimeSyncService", function(context)
		context.TimeSyncService = require(script.Parent.Services.TimeSyncService)
		Diagnostics.assert(context.TimeSyncService ~= nil, "TimeSyncService failed to load")
		context.TimeSyncService.start()
	end)

	startEntry(ctx, started, "StaggerSystem", function(context)
		context.StaggerSystem = require(script.Parent.Services.StaggerSystem)
		Diagnostics.assert(context.StaggerSystem ~= nil, "StaggerSystem failed to load")
		context.StaggerSystem.init()
	end, { "CombatAndStatus" })

	startEntry(ctx, started, "SessionHeartbeat", function(context)
		if context.SessionManager then
			context.SessionManager.startHeartbeat()
		end
	end, { "SkillsFramework" })

	startEntry(ctx, started, "PlayerLifecycle", function(context)
		local registrar = context.Registrar
		local statsManager = context.StatsManager
		local skillMetadataService = context.SkillMetadataService
		local inventoryService = context.InventoryService

		local function handleCharacter(player: Player, character: Model)
			registrar.registerEntity(character, true)
			task.defer(function()
				statsManager.initializePlayerStats(player)
				if inventoryService then
					inventoryService.initializePlayer(player)
				end
				task.delay(0.5, function()
					skillMetadataService.updateAllSkills(player)
				end)
				if context.Dev and context.Dev.onPlayerReady then
					context.Dev.onPlayerReady(player, character)
				end
			end)
		end

		local function handlePlayer(player: Player)
			player.CharacterAdded:Connect(function(character)
				handleCharacter(player, character)
			end)
			if player.Character then
				handleCharacter(player, player.Character)
			end
		end

		Players.PlayerAdded:Connect(handlePlayer)
		for _, player in ipairs(Players:GetPlayers()) do
			handlePlayer(player)
		end

		Players.PlayerRemoving:Connect(function(player)
			if context.Dev and context.Dev.onPlayerRemoving then
				context.Dev.onPlayerRemoving(player)
			end
			statsManager.cleanupPlayerStats(player)
			registrar.unregisterPlayer(player)
		end)
	end, { "Registrar", "Stats", "SkillsFramework" })

	startEntry(ctx, started, "DevHooks", function(context)
		local dev = require(script.Parent.dev.InitDev)
		dev.start(context)
		context.Dev = dev
	end, nil, true)

	Diagnostics.info("Server bootstrap complete")
	return ctx
end

return Bootstrap
