--!strict
-- Shared item type definitions for inventory/equipment systems.
--
-- The string-union types below are the closed sets equipment authoring is checked against.
-- ItemEnums.luau holds the matching runtime constant tables -- author items with
-- `ItemEnums.WeaponClass.Sword` rather than a bare `"sword"` so a typo is a type error at
-- authoring time instead of a silent fallback at swing time. Adding a new value means adding it
-- in BOTH places; ItemEnums documents the recipe.

export type ItemCategory = "consumable" | "equipment" | "material" | "quest" | "misc"
export type ItemRarity = "normal" | "magic" | "rare" | "unique"
export type AffixKind = "prefix" | "suffix"
export type ModifierContainer = "stat" | "attribute"
export type ModifierScope = "global" | "attribute" | "weapon" | "skill"
export type EquipmentVisualMode = "socketed" | "segmented" | "skinned"
export type WeaponHandedness = "one_handed" | "two_handed"
export type OffhandType = "shield" | "quiver" | "catalyst" | "focus" | "utility"

-- Canonical equipment slot ids. EquipmentSlotSchema (shared/ui) re-exports this rather than keeping
-- a second list, and owns only their display order.
export type EquipSlot =
	"Main"
	| "Secondary"
	| "Head"
	| "Neck"
	| "Body"
	| "Hands"
	| "Waist"
	| "Feet"
	| "Ring1"
	| "Ring2"

-- What kind of equipment an item is, independent of which slot it goes in. Drives nothing
-- mechanical on its own today; it is the authoring-level category the validator checks against
-- the item's weapon/offhand blocks for consistency.
export type EquipmentClass =
	"weapon"
	| "offhand"
	| "body_armor"
	| "helmet"
	| "gloves"
	| "boots"
	| "belt"
	| "amulet"
	| "ring"

-- Weapon base classes. BasicAttackProfileRegistry indexes profiles by these, so a class with no
-- registered profile silently falls back to unarmed_basic -- keep the two in sync.
export type WeaponClass = "sword" | "dagger" | "axe" | "mace" | "wand" | "staff" | "bow"

-- Damage types a weapon range or attack packet can carry.
--
-- A type does not need a matching `<Type>Damage` stat: BaseSkill.resolveFlatDamageBonus returns 0
-- for types that have none, which is a legitimate authoring state (see D2). Fire has no stat yet, so
-- it deals damage but takes no flat scaling.
export type DamageType = "Physical" | "Magic" | "Fire"

-- Which affix pool an item rolls from (AffixTierDef.modifiersByContext keys). An item whose
-- context no affix declares rolls nothing but "any" entries -- the validator warns about this.
export type AffixContext =
	"melee_weapon"
	| "magic_weapon"
	| "ranged_weapon"
	| "weapon"
	| "shield"
	| "body_armor"
	| "helmet"
	| "gloves"
	| "boots"
	| "any"

-- Descriptors read by runtime checks (CombatLoadoutResolver looks for "ranged", skill weapon
-- requirements match against them).
--
-- Tag and slot *collections* are typed as `{ ItemTag }` / `{ EquipSlot }` rather than `{ string }`.
-- Luau checks array types invariantly, so this is load-bearing: against a `{ string }` field an
-- inline `tags = { ItemEnums.Tag.Ranged }` infers as `{ ItemTag }` and is rejected, forcing every
-- item file to launder its lists through annotated locals. Helpers consuming these lists take the
-- union element type for the same reason.
export type ItemTag =
	"weapon"
	| "melee"
	| "ranged"
	| "magic"
	| "slashing"
	| "piercing"
	| "blunt"
	| "shield"
	| "armor"
	| "light"
	| "heavy"

-- Movement integrators registered in ProjectileService (`movementTypes`). A key with no
-- registered integrator falls back to linear motion.
export type ProjectileMovementType = "linear" | "parabolic" | "homing"

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
	-- Where this modifier applies. `nil` defaults to "global" (see EquipmentDefUtils.resolveScope).
	scope: ModifierScope?,
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
	-- Where the rolled modifier applies once instantiated. `nil` defaults to "global".
	scope: ModifierScope?,
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
	scope: ModifierScope?,
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

-- Weapon base damage is a fixed per-hit range for every copy of a given base item.
-- Instance variance comes from affixes (scope = "weapon"), not from a generation-time roll.
export type WeaponDamageRange = {
	type: DamageType,
	min: number,
	max: number,
}

export type WeaponBaseConfig = {
	attackSpeed: number,
	range: number?,
	critChance: number?,
}

-- The projectile a weapon fires on a projectile-delivery basic attack step.
--
-- The weapon owns the projectile's identity (which bolt, how fast, how it flies); the
-- BasicAttackProfile only owns whether a given step fires one at all (BasicAttackStepSpec.delivery).
-- That split is the same one D7 draws for damage -- the weapon says *what*, the profile says
-- *when* -- and it is what lets one `wand_light_1h` profile serve a plain wand, a flame wand and a
-- frost wand without a profile per element.
--
-- The required fields have no defensible universal default: how fast a bolt flies and how long it
-- lives are properties of the weapon, not of the attack firing it, so no skill-side constant stands
-- in for them. ProjectileService owns the defaults for the optional ones.
export type WeaponProjectileConfig = {
	templateKey: string,
	-- Name of an Attachment on the weapon's own asset (same namespace as an
	-- EquipmentVisualProfile's `assetSocket`), marking where the projectile leaves the weapon.
	--
	-- Supplies the spawn POSITION only; its orientation is ignored, so the attachment only has to sit
	-- in the right place. Direction comes from the player's aim at activation (see
	-- BasicAttack:fireProjectileStep) -- a bolt leaving along whatever way the tip happens to point
	-- is not aimable. EquipmentAuthoringValidator checks the attachment exists at startup.
	muzzleSocket: string,
	launchSpeed: number,
	lifetime: number,
	movementType: ProjectileMovementType?,
	gravity: number?,
	radius: number?,
	-- Number of entities a single projectile may damage before it despawns.
	pierce: number?,
	-- Only read when movementType == "homing".
	homing: {
		turnRate: number?,
		maxRange: number?,
		reacquire: boolean?,
	}?,
	-- Passed through to the client visual recipe untouched (e.g. { impactKey = "..." }).
	extraData: { [string]: any }?,
}

export type WeaponConfig = {
	class: WeaponClass,
	handedness: WeaponHandedness,
	tags: { ItemTag }?,
	base: WeaponBaseConfig,
	damage: { WeaponDamageRange },
	basicAttackProfile: string?,
	projectile: WeaponProjectileConfig?,
	allowedSlots: { EquipSlot }?,
	canPairWith: { WeaponClass }?,
}

export type OffhandConfig = {
	type: OffhandType,
	tags: { ItemTag }?,
	allowedSlots: { EquipSlot }?,
	blockProvider: boolean?,
	supportsWeaponClasses: { WeaponClass }?,
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
	slots: { EquipSlot },
	class: EquipmentClass,
	affixContext: AffixContext?,
	requirements: EquipmentRequirements?,
	baseRolls: { EquipmentModifierRollDef }?,
	capabilities: ItemCapability?,
	visualProfileId: string?,
	weapon: WeaponConfig?,
	offhand: OffhandConfig?,
}

export type ItemDef = {
	id: string,
	name: string,
	category: ItemCategory,
	rarity: ItemRarity?,
	stackLimit: number,
	icon: string?,
	tags: { ItemTag }?,
	equipment: EquipmentConfig?,
	equipSlots: { EquipSlot }?,
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

export type CombatLoadoutWeapon = {
	slot: string,
	uid: string,
	itemId: string,
	weaponClass: WeaponClass,
	handedness: WeaponHandedness,
	tags: { ItemTag },
	attackSpeed: number,
	range: number?,
	critChance: number?,
	damage: { WeaponDamageRange },
	basicAttackProfile: string?,
	-- Carried off the item's WeaponConfig so projectile steps read it from the loadout snapshot
	-- without a Registry lookup at swing time.
	projectile: WeaponProjectileConfig?,
}

export type CombatLoadoutOffhand = {
	slot: string,
	uid: string,
	itemId: string,
	offhandType: OffhandType,
	tags: { ItemTag },
	blockProvider: boolean?,
	supportsWeaponClasses: { WeaponClass }?,
}

-- The Secondary equipment slot holds either a one-handed weapon or an offhand item, never both.
-- Collapsed into one field so consumers check `kind` instead of both `secondary` and `offhand`.
export type CombatLoadoutSecondary = {
	kind: "weapon" | "offhand",
	weapon: CombatLoadoutWeapon?,
	offhand: CombatLoadoutOffhand?,
}

export type CombatLoadoutSnapshot = {
	entityId: string,
	version: number,
	main: CombatLoadoutWeapon?,
	secondary: CombatLoadoutSecondary?,
	modes: {
		canBlock: boolean,
		canDualWield: boolean,
		canRangedAttack: boolean,
	},
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
	kind: "snapshot" | "delta" | "projection" | "loadout",
	snapshot: InventorySnapshot?,
	delta: InventoryDelta?,
	projection: EquipmentProjectionSnapshot?,
	loadout: CombatLoadoutSnapshot?,
	sequence: number?,
}

local ItemTypes = {}

return ItemTypes
