--!strict

local ItemTypes = require(script.Parent.Parent.Parent.ItemTypes)

local glovesTier1: { ItemTypes.AffixModifierRollDef } = {
	{ kind = "percent", target = "AttackSpeed", min = 0.03, max = 0.06, scaleMinPerItemLevel = 0.002, scaleMaxPerItemLevel = 0.003 },
}
local anyTier1: { ItemTypes.AffixModifierRollDef } = {
	{ kind = "flat", target = "StaminaRegeneration", min = 0.5, max = 1.4, scaleMinPerItemLevel = 0.03, scaleMaxPerItemLevel = 0.05 },
}

local tiers: { ItemTypes.AffixTierDef } = {
	{
		tier = 1,
		minItemLevel = 1,
		weight = 100,
		labels = { "of Swiftness" },
		modifiersByContext = {
			gloves = glovesTier1,
			any = anyTier1,
		},
	},
}

local def: ItemTypes.AffixDef = {
	id = "of_swiftness",
	kind = "suffix",
	weight = 70,
	tiers = tiers,
}

return def
