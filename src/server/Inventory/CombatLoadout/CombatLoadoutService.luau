--!strict
-- Owns combat loadout recompute/versioning/replication.

local ItemTypes = require(game:GetService("ReplicatedStorage").Shared.items.ItemTypes)
local EquipmentRepository = require(script.Parent.Parent.Domain.EquipmentRepository)
local CombatLoadoutResolver = require(script.Parent.CombatLoadoutResolver)

local CombatLoadoutService = {}

local itemGetter: ((uid: string) -> ItemTypes.ItemInstance?)? = nil
local emitter: ((entityId: string, snapshot: ItemTypes.CombatLoadoutSnapshot) -> ())? = nil
local currentByEntity: { [string]: ItemTypes.CombatLoadoutSnapshot } = {}
local versionByEntity: { [string]: number } = {}

function CombatLoadoutService.setItemGetter(getter: (uid: string) -> ItemTypes.ItemInstance?)
	itemGetter = getter
end

function CombatLoadoutService.setEmitter(fn: (entityId: string, snapshot: ItemTypes.CombatLoadoutSnapshot) -> ())
	emitter = fn
end

function CombatLoadoutService.get(entityId: string): ItemTypes.CombatLoadoutSnapshot?
	return currentByEntity[entityId]
end

function CombatLoadoutService.recompute(entityId: string): ItemTypes.CombatLoadoutSnapshot
	if not itemGetter then
		error("CombatLoadoutService: item getter is not configured")
	end

	local equip = EquipmentRepository.ensure(entityId)
	local snapshot = CombatLoadoutResolver.resolve(entityId, equip, itemGetter)
	local version = (versionByEntity[entityId] or 0) + 1
	versionByEntity[entityId] = version
	snapshot.version = version
	currentByEntity[entityId] = snapshot

	if emitter then
		emitter(entityId, snapshot)
	end

	return snapshot
end

return CombatLoadoutService
