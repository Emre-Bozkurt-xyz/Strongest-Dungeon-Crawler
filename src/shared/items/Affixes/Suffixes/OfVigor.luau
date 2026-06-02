--!strict

local ItemTypes = require(script.Parent.Parent.Parent.ItemTypes)

local anyTier1: { ItemTypes.AffixModifierRollDef } = {
	{ kind = "flat", target = "Health", min = 8, max = 20, scaleMinPerItemLevel = 0.3, scaleMaxPerItemLevel = 0.6 },
}

local tiers: { ItemTypes.AffixTierDef } = {
	{
		tier = 1,
		minItemLevel = 1,
		weight = 100,
		labels = { "of Vigor" },
		modifiersByContext = {
			any = anyTier1,
		},
	},
}

local def: ItemTypes.AffixDef = {
	id = "of_vigor",
	kind = "suffix",
	weight = 100,
	tiers = tiers,
}

return def
