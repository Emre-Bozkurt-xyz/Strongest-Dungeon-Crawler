--!strict
local ItemTypes = require(script.Parent.Parent.ItemTypes)

local def: ItemTypes.ItemDef = {
	id = "mana_potion",
	name = "Mana Potion",
	category = "consumable",
	stackLimit = 20,
	icon = "",
	tags = { "consumable", "potion" },
	useAction = "ManaPotion",
	metadata = {
		chargesMax = 3,
		chargesConsumed = 1,
		refillRule = "on_kill",
		refillAmount = 1,
		restorePool = "Mana",
		restoreAmount = 25,
	},
	stackSensitiveMeta = {
		chargesMax = true,
	},
}

return def
