--!strict
-- Owns combat loadout recompute/versioning/replication.

local ItemTypes = require(game:GetService("ReplicatedStorage").Shared.items.ItemTypes)
local EquipmentRepository = require(script.Parent.Parent.Domain.EquipmentRepository)
local CombatLoadoutResolver = require(script.Parent.CombatLoadoutResolver)

local CombatLoadoutService = {}

type ShapeSelector = (entityId: string, snapshot: ItemTypes.CombatLoadoutSnapshot) -> string?

local itemGetter: ((uid: string) -> ItemTypes.ItemInstance?)? = nil
local emitter: ((entityId: string, snapshot: ItemTypes.CombatLoadoutSnapshot) -> ())? = nil
local shapeSelector: ShapeSelector? = nil
local changedListeners: { (entityId: string, snapshot: ItemTypes.CombatLoadoutSnapshot) -> () } = {}
local currentByEntity: { [string]: ItemTypes.CombatLoadoutSnapshot } = {}
local versionByEntity: { [string]: number } = {}

function CombatLoadoutService.setItemGetter(getter: (uid: string) -> ItemTypes.ItemInstance?)
	itemGetter = getter
end

function CombatLoadoutService.setEmitter(fn: (entityId: string, snapshot: ItemTypes.CombatLoadoutSnapshot) -> ())
	emitter = fn
end

-- Decides the basic attack shape written into each snapshot. Injected (FormService) rather than
-- required, since the selection lives in the player's save and this module only knows equipment.
function CombatLoadoutService.setShapeSelector(selector: ShapeSelector)
	shapeSelector = selector
end

-- Called after every recompute, once the snapshot has been sent to its owner.
function CombatLoadoutService.onChanged(listener: (entityId: string, snapshot: ItemTypes.CombatLoadoutSnapshot) -> ())
	table.insert(changedListeners, listener)
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
	snapshot.basicAttackShape = if shapeSelector then shapeSelector(entityId, snapshot) else nil
	local version = (versionByEntity[entityId] or 0) + 1
	versionByEntity[entityId] = version
	snapshot.version = version
	currentByEntity[entityId] = snapshot

	if emitter then
		emitter(entityId, snapshot)
	end
	for _, listener in ipairs(changedListeners) do
		task.spawn(listener, entityId, snapshot)
	end

	return snapshot
end

return CombatLoadoutService
