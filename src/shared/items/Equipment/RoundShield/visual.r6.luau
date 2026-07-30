--!strict

local RS = game:GetService("ReplicatedStorage")
local items = RS:WaitForChild("Shared"):WaitForChild("items")
assert(items, "RoundShield visual package must be under Shared.items")
local ItemTypes = require(items.ItemTypes)

local profile: ItemTypes.EquipmentVisualProfile = {
	id = "round_shield_r6",
	rig = "R6",
	mode = "socketed",
	-- Secondary only; equipment.slots does not permit Main.
	socketedSlots = {
		Secondary = {
			asset = "RoundShield",
			characterSocket = "Weapon_Offhand",
			assetSocket = "ItemGrip",
			offset = CFrame.new(),
		},
	},
}

return profile
