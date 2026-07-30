--!strict

local ItemTypes = require(script.Parent.Parent.Parent.ItemTypes)

local meleeWeaponTier1: { ItemTypes.AffixModifierRollDef } = {
	{ kind = "flat", target = "PhysicalDamage", min = 1, max = 3, scaleMinPerItemLevel = 0.08, scaleMaxPerItemLevel = 0.15, scope = "weapon" },
}
local glovesTier1: { ItemTypes.AffixModifierRollDef } = {
	{ kind = "percent", target = "AttackSpeed", min = 0.03, max = 0.06, scaleMinPerItemLevel = 0.002, scaleMaxPerItemLevel = 0.003 },
}
local bodyArmorTier1: { ItemTypes.AffixModifierRollDef } = {
	{ kind = "flat", target = "Strength", min = 1, max = 2, scaleMinPerItemLevel = 0.05, scaleMaxPerItemLevel = 0.08, container = "attribute" },
}

local meleeWeaponTier2: { ItemTypes.AffixModifierRollDef } = {
	{ kind = "flat", target = "PhysicalDamage", min = 4, max = 8, scaleMinPerItemLevel = 0.12, scaleMaxPerItemLevel = 0.2, scope = "weapon" },
}
local glovesTier2: { ItemTypes.AffixModifierRollDef } = {
	{ kind = "percent", target = "AttackSpeed", min = 0.07, max = 0.13, scaleMinPerItemLevel = 0.002, scaleMaxPerItemLevel = 0.004 },
}
local bodyArmorTier2: { ItemTypes.AffixModifierRollDef } = {
	{ kind = "flat", target = "Strength", min = 3, max = 5, scaleMinPerItemLevel = 0.08, scaleMaxPerItemLevel = 0.12, container = "attribute" },
}

local tiers: { ItemTypes.AffixTierDef } = {
	{
		tier = 1,
		minItemLevel = 1,
		weight = 100,
		labels = { "Furious", "Raging" },
		modifiersByContext = {
			melee_weapon = meleeWeaponTier1,
			gloves = glovesTier1,
			body_armor = bodyArmorTier1,
		},
	},
	{
		tier = 2,
		minItemLevel = 14,
		weight = 70,
		labels = { "Savage", "Bloodfury" },
		modifiersByContext = {
			melee_weapon = meleeWeaponTier2,
			gloves = glovesTier2,
			body_armor = bodyArmorTier2,
		},
	},
}

local def: ItemTypes.AffixDef = {
	id = "fury",
	kind = "prefix",
	weight = 100,
	tiers = tiers,
}

return def
