--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)

local InventoryQueryService = {}

export type SnapshotDeps = {
	inventoryEnsure: (entityId: string) -> ItemTypes.InventoryState,
	equipmentEnsure: (entityId: string) -> ItemTypes.EquipmentState,
	itemGet: (uid: string) -> ItemTypes.ItemInstance?,
}

function InventoryQueryService.snapshot(entityId: string, deps: SnapshotDeps): ItemTypes.InventorySnapshot
	local inv = deps.inventoryEnsure(entityId)
	local equip = deps.equipmentEnsure(entityId)
	local items: { [string]: ItemTypes.ItemInstance } = {}
	for _, uid in pairs(inv.slots) do
		if uid then
			local inst = deps.itemGet(uid)
			if inst then
				items[uid] = inst
			end
		end
	end
	for _, uid in pairs(equip.slots) do
		if uid then
			local inst = deps.itemGet(uid)
			if inst then
				items[uid] = inst
			end
		end
	end
	return {
		items = items,
		inventory = inv,
		equipment = equip,
	}
end

return InventoryQueryService