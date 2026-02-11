--!strict
local ItemTypes = require(script.Parent.Parent.ItemTypes)

local def: ItemTypes.ItemDef = {
	id = "leather_chest",
	name = "Leather Chestpiece",
	category = "equipment",
	stackLimit = 1,
	icon = "",
	tags = { "armor" },
	equipSlots = { "Body" },
	baseStats = {
		Armor = 3,
	},
	requirements = {
		level = 1,
		stats = { Dexterity = 5 },
	},
	metadata = {
		baseType = "chest",
	},
	visuals = {
		Body = {
			model = "LeatherChest",
			attach = "UpperTorso",
			itemAttach = "ChestMount",
			offset = CFrame.new(),
		},
	},
}

return def
