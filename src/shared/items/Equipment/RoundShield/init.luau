--!strict
local RS = game:GetService("ReplicatedStorage")
local items = RS:WaitForChild("Shared"):WaitForChild("items")
assert(items, "RoundShield item package must be under Shared.items")
local ItemTypes = require(items.ItemTypes)
local ItemEnums = require(items.ItemEnums)

local baseRolls: { ItemTypes.EquipmentModifierRollDef } = {
	{
		id = "base_roll::armor",
		kind = ItemEnums.ModifierKind.Flat,
		target = "Armor",
		min = 2,
		max = 4,
		scaleMinPerItemLevel = 0.08,
		scaleMaxPerItemLevel = 0.12,
		description = "Base armor roll",
	},
}

-- A shield is an offhand, not armour: it sits in Secondary opposite the main-hand weapon. This block
-- is what separates "an item that happens to occupy Secondary" from "an item combat understands as
-- a shield" -- without it CombatLoadoutResolver.resolveSlot finds neither a weapon nor an offhand
-- config and the slot reads as empty to every combat system.
local offhand: ItemTypes.OffhandConfig = {
	type = ItemEnums.OffhandType.Shield,
	tags = { ItemEnums.Tag.Shield, ItemEnums.Tag.Light },
	-- Read by CombatLoadoutResolver to set modes.canBlock.
	blockProvider = true,
	allowedSlots = { ItemEnums.EquipSlot.Secondary },
	-- supportsWeaponClasses omitted = pairs with any one-handed weapon. Narrow it only for an
	-- offhand that requires a specific class, like a quiver needing a bow.
}

local equipment: ItemTypes.EquipmentConfig = {
	itemLevel = 1,
	slots = { ItemEnums.EquipSlot.Secondary },
	class = ItemEnums.EquipmentClass.Offhand,
	affixContext = ItemEnums.AffixContext.Shield,
	requirements = {
		level = 1,
		attributes = { Strength = 2 },
	},
	baseRolls = baseRolls,
	offhand = offhand,
	visualProfileId = "round_shield_r6",
}

local def: ItemTypes.ItemDef = {
	id = "round_shield",
	name = "Round Shield",
	category = ItemEnums.ItemCategory.Equipment,
	stackLimit = 1,
	icon = "",
	tags = { ItemEnums.Tag.Shield, ItemEnums.Tag.Armor, ItemEnums.Tag.Light },
	equipment = equipment,
	metadata = {
		baseType = "shield",
	},
}

return def
