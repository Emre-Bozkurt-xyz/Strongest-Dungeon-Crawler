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
--
-- Reload (dev tooling; it makes the PlayerDataService save swap under a live player itself):
-- everything a session start restores is dropped and restored again from the save now in use, on
-- the same body, and the services that read the save directly hear about it through
-- PlayerDataService.onLoaded.
-- Session-only state that no save holds -- owned skills, base stat values, dev setup -- is left to
-- whoever granted it.

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
local CooldownService = require(Server.SkillsFramework.CooldownService)
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

-- What a body is in the middle of: its skill in progress and its status effects.
local function endBodyState(entityId: string, reason: string)
	local active = SessionManager.getActive(entityId)
	if active then
		SessionManager.cancel(active.id, reason)
	end
	StatusEffectsService.clearAll(entityId)
end

local function respawn(player: Player)
	local entityId = Registrar.getPlayerId(player)
	if not entityId then
		return
	end
	endBodyState(entityId, "respawned")
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

-- Rebuild the player's live state from what PlayerDataService.get returns, as a session start
-- would, without a new character. `swap`, when given, changes which save is in use
-- (PlayerDataService.enterSandbox / exitSandbox) and returns whether it did; reload calls it itself,
-- at the one point where that is safe. Yields one frame, so the recomputes that changes defer
-- (passives, gear requirements) have run before pools refill to their new maximums. False, with a
-- reason, when the player's session has not been restored yet, the swap did not happen, or they
-- left meanwhile.
function PlayerSession.reload(player: Player, swap: (() -> boolean)?): (boolean, string?)
	local entityId = Registrar.getPlayerId(player)
	if not restored[player] or not PlayerDataService.get(player) or not entityId then
		return false, "session not restored yet"
	end

	endBodyState(entityId, "reloaded")
	CooldownService.clearAll(entityId, "reloaded")
	local current = PlayerDataService.get(player)
	if not restored[player] or not current then
		return false, "player left"
	end

	-- Live state goes into the save it came from, then the write-back guard is off from before the
	-- swap until live state has been rebuilt from the save in use after it. In between, live state
	-- belongs to the other save: a save or a leave taken then, with the guard on, would write a
	-- preset's character into the real profile. Because the guard is cleared here, before the swap
	-- and in the same place, the ordering holds whatever yields in between.
	if swap then
		writeLiveState(player, current)
	end
	restored[player] = nil
	if swap and not swap() then
		-- Nothing was swapped: live state is still the save in use's.
		restored[player] = if player.Parent == Players then true else nil
		return false, "save not loaded"
	end
	local data = PlayerDataService.get(player)
	if not data then
		return false, "player left"
	end
	InventoryService.releasePlayer(entityId)
	AttributesManager.restoreSaved(player, data.attributes)
	InventoryService.initializePlayer(player, data.inventory)
	restored[player] = true
	-- Releasing equipment fires no slot events, so slots the new save leaves empty keep their old
	-- visuals until rebuilt from what is equipped now.
	EquipmentVisualService.refresh(entityId)

	PlayerDataService.replayLoaded(player)

	task.wait()
	if player.Parent ~= Players or Registrar.getPlayerId(player) ~= entityId then
		return false, "player left"
	end
	refillPools(entityId)
	SkillMetadataService.updateAllSkills(player)
	return true, nil
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
