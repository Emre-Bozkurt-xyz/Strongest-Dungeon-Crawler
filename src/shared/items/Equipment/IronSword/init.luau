--!strict
local itemsRoot = script:FindFirstAncestor("items")
assert(itemsRoot, "IronSword item package must be under Shared.items")
local ItemTypes = require(itemsRoot.ItemTypes)

local baseRolls: { ItemTypes.EquipmentModifierRollDef } = {
	{
		id = "base_roll::physical_damage",
		kind = "flat",
		target = "PhysicalDamage",
		min = 5,
		max = 7,
		scaleMinPerItemLevel = 0.12,
		scaleMaxPerItemLevel = 0.18,
		description = "Base physical damage roll",
	},
	{
		id = "base_roll::attack_speed",
		kind = "flat",
		target = "AttackSpeed",
		min = 0.95,
		max = 1.05,
		scaleMinPerItemLevel = 0.002,
		scaleMaxPerItemLevel = 0.003,
		description = "Base attack speed roll",
	},
}

local equipment: ItemTypes.EquipmentConfig = {
	itemLevel = 1,
	slots = { "Main", "Secondary" },
	class = "sword",
	affixContext = "melee_weapon",
	requirements = {
		level = 1,
		attributes = { Strength = 5 },
	},
	baseRolls = baseRolls,
	visualProfileId = "iron_sword_r6",
}

local def: ItemTypes.ItemDef = {
	id = "iron_sword",
	name = "Iron Sword",
	category = "equipment",
	stackLimit = 1,
	icon = "",
	tags = { "weapon", "melee" },
	equipment = equipment,
	metadata = {
		baseType = "sword",
	},
}

return def
