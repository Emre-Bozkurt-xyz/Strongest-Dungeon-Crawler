--!strict
-- Shared item type definitions for inventory/equipment systems.

export type ItemCategory = "consumable" | "equipment" | "material" | "quest" | "misc"
export type ItemRarity = "normal" | "magic" | "rare" | "unique"

export type StackSensitiveMeta = { [string]: boolean }

export type ItemMeta = {
	chargesMax: number?,
	chargesConsumed: number?,
	chargesCurrent: number?,
	[string]: any,
}

export type ItemDef = {
	id: string,
	name: string,
	category: ItemCategory,
	stackLimit: number,
	icon: string?,
	tags: { string }?,
	equipSlots: { string }?,
	visuals: { [string]: {
		model: string,
		attach: string?,
		itemAttach: string?,
		offset: CFrame?,
	} }?,
	useAction: string?,
	baseStats: { [string]: number }?,
	requirements: {
		level: number?,
		stats: { [string]: number }?,
	}?,
	metadata: ItemMeta?,
	stackSensitiveMeta: StackSensitiveMeta?,
}

export type ItemInstance = {
	uid: string,
	itemId: string,
	stackSize: number,
	meta: ItemMeta?,
}

export type InventoryState = {
	ownerId: string,
	capacity: number,
	slots: { [number]: string? },
	stacks: { [string]: { string } },
}

export type EquipmentState = {
	ownerId: string,
	slots: { [string]: string? },
}

export type InventorySnapshot = {
	items: { [string]: ItemInstance },
	inventory: InventoryState,
	equipment: EquipmentState,
}

export type InventoryDelta =
	{ kind: "item_added", item: ItemInstance }
	| { kind: "item_updated", item: ItemInstance }
	| { kind: "item_removed", uid: string }
	| { kind: "inventory_slot", slot: number, uid: string? }
	| { kind: "inventory_capacity", capacity: number }
	| { kind: "equipment_slot", slot: string, uid: string? }

local ItemTypes = {}

return ItemTypes
