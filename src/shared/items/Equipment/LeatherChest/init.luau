--!strict
local RS = game:GetService("ReplicatedStorage")
local items = RS:WaitForChild("Shared"):WaitForChild("items")
assert(items, "LeatherChest item package must be under Shared.items")
local ItemTypes = require(items.ItemTypes)
local ItemEnums = require(items.ItemEnums)

local baseRolls: { ItemTypes.EquipmentModifierRollDef } = {
	{
		id = "base_roll::armor",
		kind = ItemEnums.ModifierKind.Flat,
		target = "Armor",
		min = 2,
		max = 4,
		scaleMinPerItemLevel = 0.08,
		scaleMaxPerItemLevel = 0.12,
		description = "Base armor roll",
	},
}

local equipment: ItemTypes.EquipmentConfig = {
	itemLevel = 1,
	slots = { ItemEnums.EquipSlot.Body },
	class = ItemEnums.EquipmentClass.BodyArmor,
	affixContext = ItemEnums.AffixContext.BodyArmor,
	requirements = {
		level = 1,
		attributes = { Dexterity = 5 },
	},
	baseRolls = baseRolls,
	visualProfileId = "leather_chest_r6_rigid",
}

local def: ItemTypes.ItemDef = {
	id = "leather_chest",
	name = "Leather Chestpiece",
	category = ItemEnums.ItemCategory.Equipment,
	stackLimit = 1,
	icon = "",
	tags = { ItemEnums.Tag.Armor },
	equipment = equipment,
	metadata = {
		baseType = "chest",
	},
}

return def
