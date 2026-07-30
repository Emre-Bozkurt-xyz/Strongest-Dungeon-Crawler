--!strict
-- Authoring enums for items and equipment: the runtime constant tables that back the string-union
-- types in ItemTypes.luau.
--
-- WHY THIS EXISTS
-- Equipment definitions are almost entirely string fields, and a mistyped string is not an error --
-- it is a silent fallback. `class = "swrod"` resolves no basic attack profile and quietly degrades
-- to unarmed; `affixContext = "sheild"` rolls nothing but "any" affixes forever. Writing
-- `ItemEnums.WeaponClass.Sword` instead makes those typos a type error, gives autocomplete in the
-- editor, and gives one place to read off every legal value for a field.
--
-- HOW TO USE IT (in an Equipment/<Name>/init.luau)
--   local ItemEnums = require(items.ItemEnums)
--   local weapon: ItemTypes.WeaponConfig = {
--       class = ItemEnums.WeaponClass.Wand,
--       handedness = ItemEnums.Handedness.OneHanded,
--       tags = { ItemEnums.Tag.Magic, ItemEnums.Tag.Ranged },
--       damage = { { type = ItemEnums.DamageType.Magic, min = 8, max = 12 } },
--       ...
--   }
--
-- HOW TO ADD A VALUE
--   1. Add it to the union in ItemTypes.luau.
--   2. Add it to the matching table here.
--   3. If it is a WeaponClass, register a BasicAttackProfile for it (otherwise it falls back to
--      unarmed_basic). If it is an AffixContext, author affix entries for it (otherwise it rolls
--      only "any" entries). EquipmentAuthoringValidator warns about both at startup.
--
-- The `:: Type` annotations are load-bearing, not decoration: without them Luau infers plain
-- `string` for each field and the whole point (assignment checking at the authoring site) is lost.
-- This mirrors the StatTypes.StaticStats pattern already used for stat names.

local ItemTypes = require(script.Parent.ItemTypes)

local ItemEnums = {}

ItemEnums.EquipSlot = {
	Main = "Main" :: ItemTypes.EquipSlot,
	Secondary = "Secondary" :: ItemTypes.EquipSlot,
	Head = "Head" :: ItemTypes.EquipSlot,
	Neck = "Neck" :: ItemTypes.EquipSlot,
	Body = "Body" :: ItemTypes.EquipSlot,
	Hands = "Hands" :: ItemTypes.EquipSlot,
	Waist = "Waist" :: ItemTypes.EquipSlot,
	Feet = "Feet" :: ItemTypes.EquipSlot,
	Ring1 = "Ring1" :: ItemTypes.EquipSlot,
	Ring2 = "Ring2" :: ItemTypes.EquipSlot,
}

ItemEnums.ItemCategory = {
	Consumable = "consumable" :: ItemTypes.ItemCategory,
	Equipment = "equipment" :: ItemTypes.ItemCategory,
	Material = "material" :: ItemTypes.ItemCategory,
	Quest = "quest" :: ItemTypes.ItemCategory,
	Misc = "misc" :: ItemTypes.ItemCategory,
}

ItemEnums.Rarity = {
	Normal = "normal" :: ItemTypes.ItemRarity,
	Magic = "magic" :: ItemTypes.ItemRarity,
	Rare = "rare" :: ItemTypes.ItemRarity,
	Unique = "unique" :: ItemTypes.ItemRarity,
}

ItemEnums.EquipmentClass = {
	Weapon = "weapon" :: ItemTypes.EquipmentClass,
	Offhand = "offhand" :: ItemTypes.EquipmentClass,
	BodyArmor = "body_armor" :: ItemTypes.EquipmentClass,
	Helmet = "helmet" :: ItemTypes.EquipmentClass,
	Gloves = "gloves" :: ItemTypes.EquipmentClass,
	Boots = "boots" :: ItemTypes.EquipmentClass,
	Belt = "belt" :: ItemTypes.EquipmentClass,
	Amulet = "amulet" :: ItemTypes.EquipmentClass,
	Ring = "ring" :: ItemTypes.EquipmentClass,
}

ItemEnums.WeaponClass = {
	Sword = "sword" :: ItemTypes.WeaponClass,
	Dagger = "dagger" :: ItemTypes.WeaponClass,
	Axe = "axe" :: ItemTypes.WeaponClass,
	Mace = "mace" :: ItemTypes.WeaponClass,
	Wand = "wand" :: ItemTypes.WeaponClass,
	Staff = "staff" :: ItemTypes.WeaponClass,
	Bow = "bow" :: ItemTypes.WeaponClass,
}

ItemEnums.Handedness = {
	OneHanded = "one_handed" :: ItemTypes.WeaponHandedness,
	TwoHanded = "two_handed" :: ItemTypes.WeaponHandedness,
}

ItemEnums.OffhandType = {
	Shield = "shield" :: ItemTypes.OffhandType,
	Quiver = "quiver" :: ItemTypes.OffhandType,
	Catalyst = "catalyst" :: ItemTypes.OffhandType,
	Focus = "focus" :: ItemTypes.OffhandType,
	Utility = "utility" :: ItemTypes.OffhandType,
}

ItemEnums.DamageType = {
	Physical = "Physical" :: ItemTypes.DamageType,
	Magic = "Magic" :: ItemTypes.DamageType,
	Fire = "Fire" :: ItemTypes.DamageType,
}

ItemEnums.AffixContext = {
	MeleeWeapon = "melee_weapon" :: ItemTypes.AffixContext,
	MagicWeapon = "magic_weapon" :: ItemTypes.AffixContext,
	RangedWeapon = "ranged_weapon" :: ItemTypes.AffixContext,
	Weapon = "weapon" :: ItemTypes.AffixContext,
	Shield = "shield" :: ItemTypes.AffixContext,
	BodyArmor = "body_armor" :: ItemTypes.AffixContext,
	Helmet = "helmet" :: ItemTypes.AffixContext,
	Gloves = "gloves" :: ItemTypes.AffixContext,
	Boots = "boots" :: ItemTypes.AffixContext,
	Any = "any" :: ItemTypes.AffixContext,
}

ItemEnums.Tag = {
	Weapon = "weapon" :: ItemTypes.ItemTag,
	Melee = "melee" :: ItemTypes.ItemTag,
	Ranged = "ranged" :: ItemTypes.ItemTag,
	Magic = "magic" :: ItemTypes.ItemTag,
	Slashing = "slashing" :: ItemTypes.ItemTag,
	Piercing = "piercing" :: ItemTypes.ItemTag,
	Blunt = "blunt" :: ItemTypes.ItemTag,
	Shield = "shield" :: ItemTypes.ItemTag,
	Armor = "armor" :: ItemTypes.ItemTag,
	Light = "light" :: ItemTypes.ItemTag,
	Heavy = "heavy" :: ItemTypes.ItemTag,
}

ItemEnums.ModifierScope = {
	Global = "global" :: ItemTypes.ModifierScope,
	Attribute = "attribute" :: ItemTypes.ModifierScope,
	Weapon = "weapon" :: ItemTypes.ModifierScope,
	Skill = "skill" :: ItemTypes.ModifierScope,
}

ItemEnums.ModifierKind = {
	Flat = "flat" :: ItemTypes.ModifierEntryKind,
	Percent = "percent" :: ItemTypes.ModifierEntryKind,
	PercentOfStat = "percent_of_stat" :: ItemTypes.ModifierEntryKind,
}

ItemEnums.ModifierContainer = {
	Stat = "stat" :: ItemTypes.ModifierContainer,
	Attribute = "attribute" :: ItemTypes.ModifierContainer,
}

ItemEnums.VisualMode = {
	Socketed = "socketed" :: ItemTypes.EquipmentVisualMode,
	Segmented = "segmented" :: ItemTypes.EquipmentVisualMode,
	Skinned = "skinned" :: ItemTypes.EquipmentVisualMode,
}

ItemEnums.ProjectileMovement = {
	Linear = "linear" :: ItemTypes.ProjectileMovementType,
	Parabolic = "parabolic" :: ItemTypes.ProjectileMovementType,
	Homing = "homing" :: ItemTypes.ProjectileMovementType,
}

-- Membership sets, built from the tables above so they cannot drift from them.
--
-- These serve the runtime validators, which receive values that were never type-checked: affix roll
-- targets are derived by string manipulation, and item defs loaded through `require` can be authored
-- without the enum tables at all. Type checking covers authoring; these cover everything that
-- reaches a registry as a plain string.
local function buildSet<T>(source: { [string]: T }): { [T]: boolean }
	local set: { [T]: boolean } = {}
	for _, value in pairs(source) do
		set[value] = true
	end
	return set
end

local EQUIP_SLOT_SET = buildSet(ItemEnums.EquipSlot)
local EQUIPMENT_CLASS_SET = buildSet(ItemEnums.EquipmentClass)
local WEAPON_CLASS_SET = buildSet(ItemEnums.WeaponClass)
local DAMAGE_TYPE_SET = buildSet(ItemEnums.DamageType)
local AFFIX_CONTEXT_SET = buildSet(ItemEnums.AffixContext)
local OFFHAND_TYPE_SET = buildSet(ItemEnums.OffhandType)

-- All of the `is*` predicates take `string` rather than the corresponding union deliberately.
-- Luau's old solver widens a singleton union to plain `string` once it crosses a module boundary,
-- so a narrowly-typed parameter would reject values this module itself produced. They are pure
-- lookups, so accepting `string` costs nothing -- an unrecognised value simply returns false.
-- (Same reasoning as EquipmentDefUtils.isProjectedScope.)
function ItemEnums.isEquipSlot(value: string): boolean
	return EQUIP_SLOT_SET[value :: any] == true
end

function ItemEnums.isEquipmentClass(value: string): boolean
	return EQUIPMENT_CLASS_SET[value :: any] == true
end

function ItemEnums.isWeaponClass(value: string): boolean
	return WEAPON_CLASS_SET[value :: any] == true
end

function ItemEnums.isDamageType(value: string): boolean
	return DAMAGE_TYPE_SET[value :: any] == true
end

function ItemEnums.isAffixContext(value: string): boolean
	return AFFIX_CONTEXT_SET[value :: any] == true
end

function ItemEnums.isOffhandType(value: string): boolean
	return OFFHAND_TYPE_SET[value :: any] == true
end

-- Sorted value lists, for error messages that tell an author what they *could* have written.
local function sortedValues(source: { [string]: any }): { string }
	local out: { string } = {}
	for _, value in pairs(source) do
		table.insert(out, value :: string)
	end
	table.sort(out)
	return out
end

function ItemEnums.listEquipSlots(): { string }
	return sortedValues(ItemEnums.EquipSlot)
end

function ItemEnums.listEquipmentClasses(): { string }
	return sortedValues(ItemEnums.EquipmentClass)
end

function ItemEnums.listWeaponClasses(): { string }
	return sortedValues(ItemEnums.WeaponClass)
end

function ItemEnums.listDamageTypes(): { string }
	return sortedValues(ItemEnums.DamageType)
end

function ItemEnums.listAffixContexts(): { string }
	return sortedValues(ItemEnums.AffixContext)
end

return ItemEnums
