--!strict

local ItemTypes = require(script.Parent.Parent.Parent.ItemTypes)

local meleeWeaponTier1: { ItemTypes.AffixModifierRollDef } = {
	{ kind = "flat", target = "CriticalHitChance", min = 1, max = 3, scaleMinPerItemLevel = 0.03, scaleMaxPerItemLevel = 0.06 },
}
local glovesTier1: { ItemTypes.AffixModifierRollDef } = {
	{ kind = "flat", target = "Dexterity", min = 1, max = 2, scaleMinPerItemLevel = 0.04, scaleMaxPerItemLevel = 0.08, container = "attribute" },
}
local bodyArmorTier1: { ItemTypes.AffixModifierRollDef } = {
	{ kind = "flat", target = "Intelligence", min = 1, max = 2, scaleMinPerItemLevel = 0.04, scaleMaxPerItemLevel = 0.08, container = "attribute" },
}
local anyTier1: { ItemTypes.AffixModifierRollDef } = {
	{ kind = "flat", target = "ManaRegeneration", min = 0.2, max = 0.8, scaleMinPerItemLevel = 0.02, scaleMaxPerItemLevel = 0.04 },
}

local tiers: { ItemTypes.AffixTierDef } = {
	{
		tier = 1,
		minItemLevel = 1,
		weight = 100,
		labels = { "of the Fairy" },
		modifiersByContext = {
			melee_weapon = meleeWeaponTier1,
			gloves = glovesTier1,
			body_armor = bodyArmorTier1,
			any = anyTier1,
		},
	},
}

local def: ItemTypes.AffixDef = {
	id = "of_the_fairy",
	kind = "suffix",
	weight = 90,
	tiers = tiers,
}

return def
