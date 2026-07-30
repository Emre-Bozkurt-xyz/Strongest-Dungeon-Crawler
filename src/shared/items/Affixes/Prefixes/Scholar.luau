--!strict

local ItemTypes = require(script.Parent.Parent.Parent.ItemTypes)

local bodyArmorTier1: { ItemTypes.AffixModifierRollDef } = {
	{ kind = "flat", target = "Intelligence", min = 1, max = 3, scaleMinPerItemLevel = 0.05, scaleMaxPerItemLevel = 0.08, container = "attribute" },
}
local glovesTier1: { ItemTypes.AffixModifierRollDef } = {
	{ kind = "percent", target = "SpellCastSpeed", min = 0.03, max = 0.07, scaleMinPerItemLevel = 0.002, scaleMaxPerItemLevel = 0.003 },
}
-- scope = "weapon" keeps this on the wand's own damage range instead of the player's MagicDamage
-- stat, the same way Fury's melee entries stay local to the weapon they roll on.
local magicWeaponTier1: { ItemTypes.AffixModifierRollDef } = {
	{ kind = "flat", target = "MagicDamage", min = 1, max = 3, scaleMinPerItemLevel = 0.08, scaleMaxPerItemLevel = 0.15, scope = "weapon" },
}
local anyTier1: { ItemTypes.AffixModifierRollDef } = {
	{ kind = "flat", target = "Mana", min = 8, max = 18, scaleMinPerItemLevel = 0.3, scaleMaxPerItemLevel = 0.6 },
}

local tiers: { ItemTypes.AffixTierDef } = {
	{
		tier = 1,
		minItemLevel = 1,
		weight = 100,
		labels = { "Sage", "Scholar's" },
		modifiersByContext = {
			body_armor = bodyArmorTier1,
			gloves = glovesTier1,
			magic_weapon = magicWeaponTier1,
			any = anyTier1,
		},
	},
}

local def: ItemTypes.AffixDef = {
	id = "scholar",
	kind = "prefix",
	weight = 60,
	tiers = tiers,
}

return def
