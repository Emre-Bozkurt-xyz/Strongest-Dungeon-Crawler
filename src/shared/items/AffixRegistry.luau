--!strict
-- Shared affix registry and rarity policy. Affix content is autoloaded from items/Affixes.

local ItemTypes = require(script.Parent.ItemTypes)
local EquipmentDefUtils = require(script.Parent.EquipmentDefUtils)

type AffixBudget = {
	prefix: number,
	suffix: number,
}

local RARITY_ROLL_WEIGHTS: { [ItemTypes.ItemRarity]: number } = {
	normal = 80,
	magic = 16,
	rare = 4,
	unique = 0,
}

local RARITY_AFFIX_BUDGET: { [ItemTypes.ItemRarity]: AffixBudget } = {
	normal = { prefix = 0, suffix = 0 },
	magic = { prefix = 1, suffix = 1 },
	rare = { prefix = 2, suffix = 2 },
	unique = { prefix = 3, suffix = 3 },
}

local AffixRegistry = {}

local byKind: { [ItemTypes.AffixKind]: { ItemTypes.AffixDef } } = {
	prefix = {},
	suffix = {},
}
local byId: { [string]: ItemTypes.AffixDef } = {}

local function registerAffix(def: ItemTypes.AffixDef, sourceName: string, expectedKind: ItemTypes.AffixKind)
	assert(type(def.id) == "string" and def.id ~= "", `Affix '{sourceName}' missing id`)
	assert(def.kind == "prefix" or def.kind == "suffix", `Affix '{def.id}' has invalid kind`)
	assert(
		def.kind == expectedKind,
		`Affix '{def.id}' is in the {expectedKind} folder but declares kind '{def.kind}'`
	)
	assert(byId[def.id] == nil, `Duplicate affix id '{def.id}'`)
	byId[def.id] = def
	table.insert(byKind[def.kind], def)
end

local function loadFolder(folder: Instance?, expectedKind: ItemTypes.AffixKind)
	if not folder then
		return
	end
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("ModuleScript") then
			local def = require(child) :: ItemTypes.AffixDef
			registerAffix(def, child:GetFullName(), expectedKind)
		end
	end
end

local affixesRoot = script.Parent:FindFirstChild("Affixes")
if affixesRoot then
	loadFolder(affixesRoot:FindFirstChild("Prefixes"), "prefix")
	loadFolder(affixesRoot:FindFirstChild("Suffixes"), "suffix")
end

for _, list in pairs(byKind) do
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
end

local function hasTag(def: ItemTypes.ItemDef, tag: string): boolean
	if not def.tags then
		return false
	end
	for _, t in ipairs(def.tags) do
		if t == tag then
			return true
		end
	end
	return false
end

local function hasSlot(def: ItemTypes.ItemDef, slot: string): boolean
	local equipSlots = EquipmentDefUtils.getEquipSlots(def)
	if not equipSlots then
		return false
	end
	for _, s in ipairs(equipSlots) do
		if s == slot then
			return true
		end
	end
	return false
end

function AffixRegistry.getRarityRollWeights(): { [ItemTypes.ItemRarity]: number }
	return table.clone(RARITY_ROLL_WEIGHTS)
end

function AffixRegistry.getAffixBudget(rarity: ItemTypes.ItemRarity): AffixBudget
	local budget = RARITY_AFFIX_BUDGET[rarity] or RARITY_AFFIX_BUDGET.normal
	return { prefix = budget.prefix, suffix = budget.suffix }
end

function AffixRegistry.listByKind(kind: ItemTypes.AffixKind): { ItemTypes.AffixDef }
	return table.clone(byKind[kind])
end

-- Does this tier grant anything on an item of `context`?
--
-- "any" is an explicit declaration that the affix applies to every item (OfVigor's flat Health),
-- not a fallback for affixes that simply have no entry for the context being asked about.
function AffixRegistry.tierAppliesToContext(tier: ItemTypes.AffixTierDef, context: string): boolean
	local defs = tier.modifiersByContext[context]
	if defs and #defs > 0 then
		return true
	end
	local anyDefs = tier.modifiersByContext.any
	return anyDefs ~= nil and #anyDefs > 0
end

-- Affixes of `kind` that can legally roll on an item of `context` at `itemLevel`.
--
-- Eligibility is by declared context: an affix that says nothing about wands cannot appear on one.
-- Without this filter every affix is a candidate for every item, and an armour prefix landing on a
-- weapon is only prevented by whatever its fallback bucket happens to contain.
function AffixRegistry.listByKindForContext(
	kind: ItemTypes.AffixKind,
	context: string,
	itemLevel: number
): { ItemTypes.AffixDef }
	local out: { ItemTypes.AffixDef } = {}
	for _, def in ipairs(byKind[kind]) do
		for _, tier in ipairs(def.tiers) do
			if itemLevel >= tier.minItemLevel and AffixRegistry.tierAppliesToContext(tier, context) then
				table.insert(out, def)
				break
			end
		end
	end
	return out
end

function AffixRegistry.list(): { ItemTypes.AffixDef }
	local out = {}
	for _, def in pairs(byId) do
		table.insert(out, def)
	end
	table.sort(out, function(a, b)
		return a.id < b.id
	end)
	return out
end

function AffixRegistry.getContext(def: ItemTypes.ItemDef): string
	local explicitContext = EquipmentDefUtils.getAffixContext(def)
	if explicitContext then
		return explicitContext
	end
	if hasTag(def, "weapon") then
		if hasTag(def, "melee") then
			return "melee_weapon"
		end
		return "weapon"
	end
	if hasSlot(def, "Hands") then
		return "gloves"
	end
	if hasSlot(def, "Body") then
		return "body_armor"
	end
	if hasSlot(def, "Head") then
		return "helmet"
	end
	if hasSlot(def, "Feet") then
		return "boots"
	end
	local equipSlots = EquipmentDefUtils.getEquipSlots(def)
	if equipSlots and #equipSlots > 0 then
		return string.lower(equipSlots[1])
	end
	return "any"
end

return AffixRegistry
