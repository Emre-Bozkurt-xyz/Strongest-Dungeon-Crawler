--!strict
local RS = game:GetService("ReplicatedStorage")
local items = RS:WaitForChild("Shared"):WaitForChild("items")
assert(items, "CrookedWand item package must be under Shared.items")
local ItemTypes = require(items.ItemTypes)
local ItemEnums = require(items.ItemEnums)

local weapon: ItemTypes.WeaponConfig = {
	class = ItemEnums.WeaponClass.Wand,
	handedness = ItemEnums.Handedness.OneHanded,
	-- "ranged" is load-bearing, not descriptive: CombatLoadoutResolver reads it to set
	-- modes.canRangedAttack on the loadout snapshot.
	tags = { ItemEnums.Tag.Magic, ItemEnums.Tag.Ranged },
	base = {
		attackSpeed = 1.2,
		critChance = 0.05,
	},
	damage = {
		{
			type = ItemEnums.DamageType.Magic,
			min = 8,
			max = 12,
		},
	},
	basicAttackProfile = "wand_light_1h",
	-- wand_light_1h says only *that* a step fires a projectile; every property of the projectile
	-- itself lives here. A flame wand is a copy of this file with `type` changed to Fire and its own
	-- templateKey -- no new profile, no new skill, no code.
	projectile = {
		-- Placeholder: reuses the existing ManaBall bolt until a wand-specific template exists.
		templateKey = "ManaBall",
		-- Attachment on the CrookedWand asset at the tip. Position only; rotation is ignored since
		-- aim comes from the cursor.
		muzzleSocket = "Muzzle",
		launchSpeed = 80,
		lifetime = 3,
		movementType = ItemEnums.ProjectileMovement.Linear,
		radius = 1.5,
		pierce = 1,
		extraData = { impactKey = "ManaBallImpact" },
	},
	allowedSlots = { ItemEnums.EquipSlot.Main, ItemEnums.EquipSlot.Secondary },
}

local equipment: ItemTypes.EquipmentConfig = {
	itemLevel = 1,
	slots = { ItemEnums.EquipSlot.Main, ItemEnums.EquipSlot.Secondary },
	class = ItemEnums.EquipmentClass.Weapon,
	affixContext = ItemEnums.AffixContext.MagicWeapon,
	requirements = {
		level = 1,
	},
	weapon = weapon,
	visualProfileId = "crooked_wand_r6",
}

local def: ItemTypes.ItemDef = {
	id = "crooked_wand",
	name = "Crooked Wand",
	category = ItemEnums.ItemCategory.Equipment,
	stackLimit = 1,
	icon = "",
	tags = { ItemEnums.Tag.Weapon, ItemEnums.Tag.Magic, ItemEnums.Tag.Ranged },
	equipment = equipment,
	metadata = {
		baseType = "wand",
	},
}

return def
