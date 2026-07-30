--!strict
local RS = game:GetService("ReplicatedStorage")
local items = RS:WaitForChild("Shared"):WaitForChild("items")
assert(items, "IronDagger item package must be under Shared.items")
local ItemTypes = require(items.ItemTypes)
local ItemEnums = require(items.ItemEnums)

local weapon: ItemTypes.WeaponConfig = {
	class = ItemEnums.WeaponClass.Dagger,
	handedness = ItemEnums.Handedness.OneHanded,
	tags = { ItemEnums.Tag.Melee, ItemEnums.Tag.Piercing },
	base = {
		-- The dagger's identity lives here rather than in dagger_light_1h's multipliers: fast and
		-- crit-prone, trading per-hit damage for swings-per-second.
		attackSpeed = 1.7,
		range = 6,
		critChance = 0.15,
	},
	damage = {
		{
			type = ItemEnums.DamageType.Physical,
			min = 4,
			max = 6,
		},
	},
	basicAttackProfile = "dagger_light_1h",
	allowedSlots = { ItemEnums.EquipSlot.Main, ItemEnums.EquipSlot.Secondary },
}

local equipment: ItemTypes.EquipmentConfig = {
	itemLevel = 1,
	slots = { ItemEnums.EquipSlot.Main, ItemEnums.EquipSlot.Secondary },
	class = ItemEnums.EquipmentClass.Weapon,
	affixContext = ItemEnums.AffixContext.MeleeWeapon,
	requirements = {
		level = 1,
	},
	weapon = weapon,
	visualProfileId = "iron_dagger_r6",
}

local def: ItemTypes.ItemDef = {
	id = "iron_dagger",
	name = "Iron Dagger",
	category = ItemEnums.ItemCategory.Equipment,
	stackLimit = 1,
	icon = "",
	tags = { ItemEnums.Tag.Weapon, ItemEnums.Tag.Melee },
	equipment = equipment,
	metadata = {
		baseType = "dagger",
	},
}

return def
