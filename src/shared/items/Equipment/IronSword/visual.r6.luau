--!strict

local itemsRoot = script:FindFirstAncestor("items")
assert(itemsRoot, "IronSword visual package must be under Shared.items")
local ItemTypes = require(itemsRoot.ItemTypes)

local profile: ItemTypes.EquipmentVisualProfile = {
	id = "iron_sword_r6",
	rig = "R6",
	mode = "socketed",
	socketedSlots = {
		Main = {
			asset = "IronSword",
			characterSocket = "Weapon_Main",
			assetSocket = "ItemGrip",
			offset = CFrame.new(),
		},
		Secondary = {
			asset = "IronSword",
			characterSocket = "Weapon_Offhand",
			assetSocket = "ItemGrip",
			offset = CFrame.new(),
		},
	},
}

return profile
