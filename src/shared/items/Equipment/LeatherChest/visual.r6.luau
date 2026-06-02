--!strict

local itemsRoot = script:FindFirstAncestor("items")
assert(itemsRoot, "LeatherChest visual package must be under Shared.items")
local ItemTypes = require(itemsRoot.ItemTypes)

local profile: ItemTypes.EquipmentVisualProfile = {
	id = "leather_chest_r6_rigid",
	rig = "R6",
	mode = "socketed",
	socketed = {
		asset = "LeatherChest",
		characterSocket = "Armor_Chest",
		assetSocket = "ArmorMount",
		offset = CFrame.new(),
	},
}

return profile
