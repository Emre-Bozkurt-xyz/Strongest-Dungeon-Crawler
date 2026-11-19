--!strict
-- Drops: keeps items in the world from crossing between a character preset's stand-in save and the
-- real one, with or without a scenario loaded.
--
-- A world drop belongs to the kind of save -- stand-in or real -- that its owner (the drop's
-- OwnerEntityId: whoever dropped it, or whoever loot is dropped for) was using when it appeared. A
-- drop with no owner belongs to the real world. A player picks up only drops of the kind of save
-- they are on now (InventoryService pickup veto). A stand-in's drops are removed when its player
-- leaves it: on restore, on applying another preset (every apply builds a new stand-in), on leaving
-- the game. Real-save drops stay in the world, out of reach of their owner while sandboxed.
--
-- Settled once per drop, while its owner is still on the save it came from: when the drop appears,
-- or just before the owner swaps saves, whichever comes first (the tag signal is deferred, so a swap
-- straight after a drop can beat it). A drop picked up loses its record, so the same item dropped
-- again is judged afresh.

local CollectionService = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")

local Server = ServerScriptService.Server
local PlayerDataService = require(Server.PlayerData.PlayerDataService)
local Registrar = require(Server.Services.Registrar)
local InventoryService = require(Server.Inventory.InventoryService)
local LootDropService = require(Server.Inventory.Domain.LootDropService)

export type Origin = {
	owner: Player?,
	sandboxed: boolean,
}

local LOOT_TAG = "LootDrop"
local OTHER_SAVE = "dev_other_save"

local Drops = {}

local origins: { [string]: Origin } = {}
local started = false

local function uidOf(drop: Instance): string?
	local uid = drop:GetAttribute("ItemUid")
	return if type(uid) == "string" then uid else nil
end

local function ownerOf(drop: Instance): Player?
	local ownerId = drop:GetAttribute("OwnerEntityId")
	if type(ownerId) ~= "string" then
		return nil
	end
	return Registrar.getPlayerById(ownerId)
end

local function record(drop: Instance): Origin?
	local uid = uidOf(drop)
	if not uid then
		return nil
	end
	local origin = origins[uid]
	if not origin then
		local owner = ownerOf(drop)
		origin = { owner = owner, sandboxed = owner ~= nil and PlayerDataService.isSandboxed(owner) }
		origins[uid] = origin
	end
	return origin
end

-- Which save a drop came from, settling it now if it has not been yet. Nil for anything that is not
-- a drop.
function Drops.origin(drop: Instance): Origin?
	return record(drop)
end

local function removeStandInDrops(player: Player)
	for uid, origin in pairs(origins) do
		if origin.owner == player and origin.sandboxed then
			origins[uid] = nil
			LootDropService.cleanup(uid)
		end
	end
end

-- Right before the player's save is swapped, while the old one is still in use.
function Drops.beforeSwap(player: Player)
	for _, drop in ipairs(CollectionService:GetTagged(LOOT_TAG)) do
		if ownerOf(drop) == player then
			record(drop)
		end
	end
	if PlayerDataService.isSandboxed(player) then
		removeStandInDrops(player)
	end
end

-- The player is leaving the game. Their drops are already settled: the tag signals of drops made
-- before they left are queued ahead of PlayerRemoving.
function Drops.release(player: Player)
	removeStandInDrops(player)
end

function Drops.start()
	if started then
		return
	end
	started = true
	for _, drop in ipairs(CollectionService:GetTagged(LOOT_TAG)) do
		record(drop)
	end
	CollectionService:GetInstanceAddedSignal(LOOT_TAG):Connect(record)
	CollectionService:GetInstanceRemovedSignal(LOOT_TAG):Connect(function(drop)
		local uid = uidOf(drop)
		if uid then
			origins[uid] = nil
		end
	end)
	InventoryService.addPickupVeto(function(_uid: string, entityId: string, drop: BasePart): string?
		local player = Registrar.getPlayerById(entityId)
		local origin = record(drop)
		if not player or not origin then
			return nil
		end
		return if origin.sandboxed ~= PlayerDataService.isSandboxed(player) then OTHER_SAVE else nil
	end)
end

return Drops
