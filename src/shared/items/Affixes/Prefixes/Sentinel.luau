--!strict

local ItemTypes = require(script.Parent.Parent.Parent.ItemTypes)

local bodyArmorTier1: { ItemTypes.AffixModifierRollDef } = {
	{ kind = "flat", target = "Armor", min = 2, max = 5, scaleMinPerItemLevel = 0.08, scaleMaxPerItemLevel = 0.15 },
	{ kind = "flat", target = "Defense", min = 1, max = 2, scaleMinPerItemLevel = 0.04, scaleMaxPerItemLevel = 0.06, container = "attribute" },
}
local glovesTier1: { ItemTypes.AffixModifierRollDef } = {
	{ kind = "flat", target = "Dexterity", min = 1, max = 2, scaleMinPerItemLevel = 0.04, scaleMaxPerItemLevel = 0.06, container = "attribute" },
}
-- Shields roll harder armor than body armor of the same item level; it is what an offhand gives up
-- a second weapon for.
local shieldTier1: { ItemTypes.AffixModifierRollDef } = {
	{ kind = "flat", target = "Armor", min = 3, max = 7, scaleMinPerItemLevel = 0.1, scaleMaxPerItemLevel = 0.2 },
	{ kind = "flat", target = "Defense", min = 1, max = 3, scaleMinPerItemLevel = 0.05, scaleMaxPerItemLevel = 0.08, container = "attribute" },
}

local tiers: { ItemTypes.AffixTierDef } = {
	{
		tier = 1,
		minItemLevel = 1,
		weight = 100,
		labels = { "Stalwart", "Guarded" },
		modifiersByContext = {
			body_armor = bodyArmorTier1,
			gloves = glovesTier1,
			shield = shieldTier1,
		},
	},
}

local def: ItemTypes.AffixDef = {
	id = "sentinel",
	kind = "prefix",
	weight = 85,
	tiers = tiers,
}

return def
