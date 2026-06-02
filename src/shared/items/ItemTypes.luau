--!strict
-- Shared item type definitions for inventory/equipment systems.

export type ItemCategory = "consumable" | "equipment" | "material" | "quest" | "misc"
export type ItemRarity = "normal" | "magic" | "rare" | "unique"
export type AffixKind = "prefix" | "suffix"
export type ModifierContainer = "stat" | "attribute"
export type EquipmentVisualMode = "socketed" | "segmented" | "skinned"

export type StackSensitiveMeta = { [string]: boolean }

export type ModifierEntryKind = "flat" | "percent" | "percent_of_stat"

export type ModifierEntry = {
	id: string?,
	kind: ModifierEntryKind,
	target: string,
	value: number,
	sourceId: string?,
	description: string?,
	tags: { string }?,
	priority: number?,
	meta: { [string]: any }?,
}

export type AffixInstance = {
	id: string,
	kind: AffixKind,
	label: string,
	tier: number,
	modifiers: { ModifierEntry },
	meta: { [string]: any }?,
}

export type AffixModifierRollDef = {
	kind: ModifierEntryKind,
	target: string,
	min: number,
	max: number,
	scaleMinPerItemLevel: number?,
	scaleMaxPerItemLevel: number?,
	container: ModifierContainer?,
	priority: number?,
	tags: { string }?,
}

export type AffixTierDef = {
	tier: number,
	minItemLevel: number,
	weight: number,
	labels: { string },
	modifiersByContext: { [string]: { AffixModifierRollDef } },
}

export type AffixDef = {
	id: string,
	kind: AffixKind,
	weight: number,
	tiers: { AffixTierDef },
}

export type SkillGrant = {
	skillName: string,
	override: { [string]: any }?,
}

export type AnimationOverrideEntry = {
	key: string,
	overrideKey: string,
	priority: number?,
}

export type EquipmentModifierRollDef = {
	id: string?,
	kind: ModifierEntryKind,
	target: string,
	min: number,
	max: number,
	scaleMinPerItemLevel: number?,
	scaleMaxPerItemLevel: number?,
	container: ModifierContainer?,
	priority: number?,
	tags: { string }?,
	description: string?,
	meta: { [string]: any }?,
}

export type EquipmentRequirements = {
	level: number?,
	stats: { [string]: number }?,
	attributes: { [string]: number }?,
}

export type SocketedVisualBinding = {
	asset: string,
	characterSocket: string,
	assetSocket: string?,
	offset: CFrame?,
}

export type SegmentedVisualBinding = {
	asset: string,
	characterSocket: string,
	assetSocket: string?,
	offset: CFrame?,
}

export type SkinnedVisualBinding = {
	asset: string,
	anchorSocket: string?,
	offset: CFrame?,
}

export type RigSocketDef = {
	name: string,
	recommendedParents: { string }?,
	legacyAliases: { string }?,
	description: string?,
}

export type RigSocketProfile = {
	id: string,
	sockets: { [string]: RigSocketDef },
}

export type EquipmentVisualProfile = {
	id: string,
	rig: string,
	mode: EquipmentVisualMode,
	socketed: SocketedVisualBinding?,
	socketedSlots: { [string]: SocketedVisualBinding }?,
	segments: { [string]: SegmentedVisualBinding }?,
	segmentsBySlot: { [string]: { [string]: SegmentedVisualBinding } }?,
	skinned: SkinnedVisualBinding?,
	skinnedSlots: { [string]: SkinnedVisualBinding }?,
}

export type ItemCapability = {
	stats: { ModifierEntry }?,
	attributes: { ModifierEntry }?,
	skills: { SkillGrant }?,
	animationOverrides: { AnimationOverrideEntry }?,
}

export type ItemMeta = {
	chargesMax: number?,
	chargesConsumed: number?,
	chargesCurrent: number?,
	itemLevel: number?,
	rarity: ItemRarity?,
	displayName: string?,
	affixes: { AffixInstance | ModifierEntry }?,
	baseModifiers: { ModifierEntry }?,
	[string]: any,
}

export type EquipmentConfig = {
	itemLevel: number?,
	slots: { string },
	class: string,
	affixContext: string?,
	requirements: EquipmentRequirements?,
	baseRolls: { EquipmentModifierRollDef }?,
	capabilities: ItemCapability?,
	visualProfileId: string?,
}

export type ItemDef = {
	id: string,
	name: string,
	category: ItemCategory,
	rarity: ItemRarity?,
	stackLimit: number,
	icon: string?,
	tags: { string }?,
	equipment: EquipmentConfig?,
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
	metadata: { [string]: any }?,
	stackSensitiveMeta: StackSensitiveMeta?,
	capabilities: ItemCapability?,
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

export type EquipmentProjectionItemStatus = {
	slot: string,
	uid: string,
	active: boolean,
	suppressedReason: string?,
}

export type EquipmentProjectionSnapshot = {
	entityId: string,
	version: number,
	appliedStats: { ModifierEntry },
	appliedAttributes: { ModifierEntry },
	grantedSkills: { SkillGrant },
	animationOverrides: { AnimationOverrideEntry },
	items: { EquipmentProjectionItemStatus },
}

export type InventoryCommand = {
	version: number,
	action: "move" | "split" | "merge" | "equip" | "unequip" | "use" | "drop" | "pickup",
	from: { container: "inventory" | "equipment", slot: number | string }?,
	to: { container: "inventory" | "equipment", slot: number | string? }?,
	uid: string?,
	count: number?,
	position: Vector3?,
}

export type InventoryRequest = {
	version: number,
	kind: "snapshot",
}

export type InventoryEvent = {
	version: number,
	kind: "snapshot" | "delta" | "projection",
	snapshot: InventorySnapshot?,
	delta: InventoryDelta?,
	projection: EquipmentProjectionSnapshot?,
	sequence: number?,
}

local ItemTypes = {}

return ItemTypes
