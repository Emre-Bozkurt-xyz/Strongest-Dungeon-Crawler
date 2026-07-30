--!strict
local RS = game:GetService("ReplicatedStorage")
local items = RS:WaitForChild("Shared"):WaitForChild("items")
assert(items, "LeatherChest visual package must be under Shared.items")
local ItemTypes = require(items.ItemTypes)

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
