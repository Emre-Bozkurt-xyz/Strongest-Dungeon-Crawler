--!strict
-- PlayerSession: the order things happen in for a player -- joining, respawning, leaving -- and when
-- their live state is written into their save.
--
-- A player keeps one entity id for the session (Registrar), so their inventory, equipment, stats
-- and skills belong to them rather than to one character. That splits a player's lifecycle in two:
--
--   - Session start, on their first character: stats, then their save, then everything restored
--     from it (attributes, inventory and equipment), then the starter kit if the save is new.
--   - Respawn, on every later character: only what belonged to the old body -- pools refill, its
--     status effects and in-progress skill end, and equipment visuals move to the new body.
--
-- Leaving writes the save first and only then lets services drop the player's state; in the other
-- order the save would capture an inventory that had already been emptied.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local StatTypes = require(ReplicatedStorage.Shared.StatTypes)

local Server = ServerScriptService.Server
local PlayerDataService = require(script.Parent.PlayerDataService)
local Registrar = require(Server.Services.Registrar)
local StatsManager = require(Server.Stats.StatsManager)
local AttributesManager = require(Server.Stats.AttributesManager)
local InventoryService = require(Server.Inventory.InventoryService)
local EquipmentVisualService = require(Server.Inventory.EquipmentVisualService)
local SessionManager = require(Server.SkillsFramework.SessionManager)
local SkillMetadataService = require(Server.SkillsFramework.SkillMetadataService)
local StatusEffectsService = require(Server.StatusEffects.StatusEffectsService)

export type Hooks = {
	-- After the player's state is restored. `grantStarterKit` is true exactly once per save.
	onSessionStart: ((player: Player, character: Model, grantStarterKit: boolean) -> ())?,
	onLeaving: ((player: Player) -> ())?,
}

local PlayerSession = {}

local started: { [Player]: boolean } = {}
-- Set once the player's state has been restored from their save. Until then their live state is
-- not theirs yet -- an empty inventory is "not loaded", not "owns nothing" -- so nothing is written
-- back.
local restored: { [Player]: boolean } = {}

local function refillPool(entityId: string, pool: StatTypes.PoolType)
	local max = StatsManager.getPoolMaxValue(entityId, pool)
	if max then
		StatsManager.addToPool(entityId, pool, max)
	end
end

-- A new body starts full. ManaShield is left alone: it is granted, not a body's own.
local function refillPools(entityId: string)
	refillPool(entityId, "Health")
	refillPool(entityId, "Mana")
	refillPool(entityId, "Stamina")
end

local function startSession(player: Player, character: Model, hooks: Hooks)
	StatsManager.initializePlayerStats(player)

	local data = PlayerDataService.waitForData(player)
	if not data or player.Parent ~= Players then
		return
	end

	AttributesManager.restoreSaved(player, data.attributes)
	InventoryService.initializePlayer(player, data.inventory)
	restored[player] = true

	-- Flipped before the kit is handed out, so a second session can never see it unset.
	local grantStarterKit = not data.starterKitGranted
	data.starterKitGranted = true

	task.delay(0.5, function()
		if player.Parent == Players then
			SkillMetadataService.updateAllSkills(player)
		end
	end)

	if hooks.onSessionStart then
		hooks.onSessionStart(player, character, grantStarterKit)
	end
end

local function respawn(player: Player)
	local entityId = Registrar.getPlayerId(player)
	if not entityId then
		return
	end
	local active = SessionManager.getActive(entityId)
	if active then
		SessionManager.cancel(active.id, "respawned")
	end
	StatusEffectsService.clearAll(entityId)
	if StatsManager.isRegistered(entityId) then
		refillPools(entityId)
	end
	EquipmentVisualService.refresh(entityId)
end

local function onCharacter(player: Player, character: Model, hooks: Hooks)
	-- Synchronously, so anything looking the new body up by entity id finds it straight away.
	Registrar.registerEntity(character, true)
	if started[player] then
		task.defer(respawn, player)
		return
	end
	started[player] = true
	task.defer(startSession, player, character, hooks)
end

local function onLeaving(player: Player, hooks: Hooks)
	if hooks.onLeaving then
		hooks.onLeaving(player)
	end

	PlayerDataService.release(player)
	restored[player] = nil
	started[player] = nil

	local entityId = Registrar.getPlayerId(player)
	if entityId then
		InventoryService.releasePlayer(entityId)
		StatsManager.cleanupPlayerStats(player)
	end
	AttributesManager.releasePlayer(player)
	Registrar.unregisterPlayer(player)
end

local function writeLiveState(player: Player, data: PlayerDataService.PlayerSaveData)
	if not restored[player] then
		return
	end
	local entityId = Registrar.getPlayerId(player)
	local inventory = entityId and InventoryService.serialize(entityId)
	if inventory then
		data.inventory = inventory
	end
	local attributes = AttributesManager.toSaved(player)
	if attributes then
		data.attributes = attributes
	end
end

function PlayerSession.start(hooks: Hooks)
	PlayerDataService.addSerializer(writeLiveState)

	local function watch(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character, hooks)
		end)
		if player.Character then
			onCharacter(player, player.Character, hooks)
		end
	end

	Players.PlayerAdded:Connect(watch)
	for _, player in ipairs(Players:GetPlayers()) do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		onLeaving(player, hooks)
	end)
end

return PlayerSession
