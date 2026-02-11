--!strict
local ItemTypes = require(script.Parent.Parent.ItemTypes)

local def: ItemTypes.ItemDef = {
	id = "iron_sword",
	name = "Iron Sword",
	category = "equipment",
	stackLimit = 1,
	icon = "",
	tags = { "weapon", "melee" },
	equipSlots = { "Main", "Secondary" },
	baseStats = {
		PhysicalDamage = 6,
		AttackSpeed = 1.0,
	},
	requirements = {
		level = 1,
		stats = { Strength = 5 },
	},
	metadata = {
		baseType = "sword",
	},
	visuals = {
		Main = {
			model = "IronSword",
			attach = "RightHand",
			itemAttach = "ItemGrip",
			offset = CFrame.new(),
		},
		Secondary = {
			model = "IronSword",
			attach = "LeftHand",
			itemAttach = "ItemGrip",
			offset = CFrame.new(),
		},
	},
}

return def
