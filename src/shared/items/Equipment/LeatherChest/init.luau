--!strict
local itemsRoot = script:FindFirstAncestor("items")
assert(itemsRoot, "LeatherChest item package must be under Shared.items")
local ItemTypes = require((itemsRoot :: any).ItemTypes)

local baseRolls: { ItemTypes.EquipmentModifierRollDef } = {
	{
		id = "base_roll::armor",
		kind = "flat",
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
	slots = { "Body" },
	class = "body_armor",
	affixContext = "body_armor",
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
	category = "equipment",
	stackLimit = 1,
	icon = "",
	tags = { "armor" },
	equipment = equipment,
	metadata = {
		baseType = "chest",
	},
}

return def
