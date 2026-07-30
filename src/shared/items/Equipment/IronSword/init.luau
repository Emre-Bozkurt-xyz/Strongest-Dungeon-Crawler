--!strict
local RS = game:GetService("ReplicatedStorage")
local items = RS:WaitForChild("Shared"):WaitForChild("items")
assert(items, "IronSword item package must be under Shared.items")
local ItemTypes = require(items.ItemTypes)
local ItemEnums = require(items.ItemEnums)

local weapon: ItemTypes.WeaponConfig = {
	class = ItemEnums.WeaponClass.Sword,
	handedness = ItemEnums.Handedness.OneHanded,
	tags = { ItemEnums.Tag.Melee, ItemEnums.Tag.Slashing },
	base = {
		attackSpeed = 1.2,
		range = 6,
		critChance = 0.05,
	},
	damage = {
		{
			type = ItemEnums.DamageType.Physical,
			min = 8,
			max = 12,
		},
	},
	basicAttackProfile = "sword_light_1h",
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
	visualProfileId = "iron_sword_r6",
}

local def: ItemTypes.ItemDef = {
	id = "iron_sword",
	name = "Iron Sword",
	category = ItemEnums.ItemCategory.Equipment,
	stackLimit = 1,
	icon = "",
	tags = { ItemEnums.Tag.Weapon, ItemEnums.Tag.Melee },
	equipment = equipment,
	metadata = {
		baseType = "sword",
	},
}

return def
