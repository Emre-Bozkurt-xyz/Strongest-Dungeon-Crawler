--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Networking = require(ReplicatedStorage.Shared.Networking)
local Registrar = require(ServerScriptService.Server.Services.Registrar)
local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)

local dispatcher = Networking.server()
local dispatcherAny = dispatcher :: any

local InventoryReplicationService = {}

local sequenceByEntity: { [string]: number } = {}

local function nextSequence(entityId: string): number
	sequenceByEntity[entityId] = (sequenceByEntity[entityId] or 0) + 1
	return sequenceByEntity[entityId]
end

local function resolvePlayer(entityId: string): Player?
	if not Registrar.isPlayerEntity(entityId) then
		return nil
	end
	return Registrar.getPlayerById(entityId)
end

function InventoryReplicationService.emitDelta(entityId: string, delta: ItemTypes.InventoryDelta)
	local player = resolvePlayer(entityId)
	if not player then
		return
	end
	dispatcherAny:emit("InventoryEvent", {
		version = 1,
		kind = "delta",
		delta = delta,
		sequence = nextSequence(entityId),
	}, { targets = player })
end

function InventoryReplicationService.emitSnapshot(entityId: string, snapshot: ItemTypes.InventorySnapshot)
	local player = resolvePlayer(entityId)
	if not player then
		return
	end
	dispatcherAny:emit("InventoryEvent", {
		version = 1,
		kind = "snapshot",
		snapshot = snapshot,
		sequence = nextSequence(entityId),
	}, { targets = player })
end

function InventoryReplicationService.emitProjection(entityId: string, projection: ItemTypes.EquipmentProjectionSnapshot)
	local player = resolvePlayer(entityId)
	if not player then
		return
	end
	dispatcherAny:emit("InventoryEvent", {
		version = 1,
		kind = "projection",
		projection = projection,
		sequence = nextSequence(entityId),
	}, { targets = player })
end

function InventoryReplicationService.emitLoadout(entityId: string, loadout: ItemTypes.CombatLoadoutSnapshot)
	local player = resolvePlayer(entityId)
	if not player then
		return
	end
	dispatcherAny:emit("InventoryEvent", {
		version = 1,
		kind = "loadout",
		loadout = loadout,
		sequence = nextSequence(entityId),
	}, { targets = player })
end

return InventoryReplicationService
