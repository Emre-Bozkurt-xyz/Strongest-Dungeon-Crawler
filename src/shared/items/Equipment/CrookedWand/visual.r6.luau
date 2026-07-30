--!strict

local RS = game:GetService("ReplicatedStorage")
local items = RS:WaitForChild("Shared"):WaitForChild("items")
assert(items, "CrookedWand visual package must be under Shared.items")
local ItemTypes = require(items.ItemTypes)

local profile: ItemTypes.EquipmentVisualProfile = {
	id = "crooked_wand_r6",
	rig = "R6",
	mode = "socketed",
	socketedSlots = {
		Main = {
			asset = "CrookedWand",
			characterSocket = "Weapon_Main",
			assetSocket = "ItemGrip",
			offset = CFrame.new(),
		},
		Secondary = {
			asset = "CrookedWand",
			characterSocket = "Weapon_Offhand",
			assetSocket = "ItemGrip",
			offset = CFrame.new(),
		},
	},
}

return profile
