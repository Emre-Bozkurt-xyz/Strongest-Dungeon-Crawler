--!strict

local RS = game:GetService("ReplicatedStorage")
local items = RS:WaitForChild("Shared"):WaitForChild("items")
assert(items, "IronDagger visual package must be under Shared.items")
local ItemTypes = require(items.ItemTypes)

local profile: ItemTypes.EquipmentVisualProfile = {
	id = "iron_dagger_r6",
	rig = "R6",
	mode = "socketed",
	socketedSlots = {
		Main = {
			asset = "IronDagger",
			characterSocket = "Weapon_Main",
			assetSocket = "ItemGrip",
			offset = CFrame.new(),
		},
		Secondary = {
			asset = "IronDagger",
			characterSocket = "Weapon_Offhand",
			assetSocket = "ItemGrip",
			offset = CFrame.new(),
		},
	},
}

return profile
