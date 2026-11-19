--!strict
-- Rolls equipment affixes and synthesizes item display names.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)
local AffixRegistry = require(ReplicatedStorage.Shared.items.AffixRegistry)
local EquipmentDefUtils = require(ReplicatedStorage.Shared.items.EquipmentDefUtils)

local AffixRollService = {}

local function cloneMeta(meta: ItemTypes.ItemMeta?): ItemTypes.ItemMeta
	if meta then
		return table.clone(meta)
	end
	return {}
end

local function clamp(value: number, minV: number, maxV: number): number
	return math.max(minV, math.min(maxV, value))
end

local function isInteger(n: number): boolean
	return math.abs(n - math.floor(n + 0.5)) < 1e-6
end

local function roundValue(v: number, asInteger: boolean): number
	if asInteger then
		return math.floor(v + 0.5)
	end
	return math.floor(v * 100 + 0.5) / 100
end

local function weightedPick<T>(entries: { T }, weightFn: (T) -> number, rng: Random): T?
	local total = 0
	for _, entry in ipairs(entries) do
		local w = weightFn(entry)
		if w > 0 then
			total += w
		end
	end
	if total <= 0 then
		return nil
	end
	local roll = rng:NextNumber(0, total)
	local acc = 0
	for _, entry in ipairs(entries) do
		local w = math.max(0, weightFn(entry))
		if w > 0 then
			acc += w
			if roll <= acc then
				return entry
			end
		end
	end
	return entries[#entries]
end

local function pickRarity(meta: ItemTypes.ItemMeta, def: ItemTypes.ItemDef, rng: Random): ItemTypes.ItemRarity
	if meta.rarity then
		return meta.rarity
	end
	if def.rarity then
		return def.rarity
	end
	local weights = AffixRegistry.getRarityRollWeights()
	local entries: { ItemTypes.ItemRarity } = { "normal", "magic", "rare", "unique" }
	local picked = weightedPick(entries, function(r)
		return weights[r] or 0
	end, rng)
	return picked or "normal"
end

-- Tiers are filtered by context as well as item level: an affix can be eligible overall while a
-- particular tier grants nothing on this item, and picking that tier would produce an affix with no
-- modifiers.
local function pickTier(
	affixDef: ItemTypes.AffixDef,
	itemLevel: number,
	context: string,
	rng: Random
): ItemTypes.AffixTierDef?
	local eligible: { ItemTypes.AffixTierDef } = {}
	for _, tier in ipairs(affixDef.tiers) do
		if itemLevel >= tier.minItemLevel and AffixRegistry.tierAppliesToContext(tier, context) then
			table.insert(eligible, tier)
		end
	end
	if #eligible == 0 then
		return nil
	end
	return weightedPick(eligible, function(tier)
		return tier.weight
	end, rng)
end

local function pickLabel(tier: ItemTypes.AffixTierDef, rng: Random): string
	if #tier.labels == 0 then
		return ""
	end
	local i = rng:NextInteger(1, #tier.labels)
	return tier.labels[i]
end

-- `any` is reached only by affixes that declared it, since eligibility filtering already excluded
-- affixes with nothing to say about this context.
local function resolveModifierDefs(
	tier: ItemTypes.AffixTierDef,
	context: string
): { ItemTypes.AffixModifierRollDef }
	local defs = tier.modifiersByContext[context]
	if defs and #defs > 0 then
		return defs
	end
	local anyDefs = tier.modifiersByContext.any
	if anyDefs and #anyDefs > 0 then
		return anyDefs
	end
	return {}
end

local function makeRolledModifier(
	affixId: string,
	affixTier: number,
	modIndex: number,
	rollDef: ItemTypes.AffixModifierRollDef,
	itemLevel: number,
	label: string,
	rng: Random
): ItemTypes.ModifierEntry
	local levelDelta = math.max(0, itemLevel - 1)
	local minV = rollDef.min + levelDelta * (rollDef.scaleMinPerItemLevel or 0)
	local maxV = rollDef.max + levelDelta * (rollDef.scaleMaxPerItemLevel or 0)
	if maxV < minV then
		local tmp = maxV
		maxV = minV
		minV = tmp
	end
	minV = clamp(minV, -999999, 999999)
	maxV = clamp(maxV, -999999, 999999)
	local raw = rng:NextNumber(minV, maxV)
	local value = roundValue(raw, isInteger(minV) and isInteger(maxV))
	local meta: { [string]: any } = {}
	if rollDef.container == "attribute" then
		meta.container = "attribute"
	end
	local id = `affix::{affixId}::t{affixTier}::m{modIndex}`
	return {
		id = id,
		kind = rollDef.kind,
		target = rollDef.target,
		value = value,
		description = `Affix '{label}'`,
		priority = rollDef.priority,
		tags = rollDef.tags,
		meta = if next(meta) ~= nil then meta else nil,
		scope = rollDef.scope,
	}
end

local function rollAffixInstances(
	def: ItemTypes.ItemDef,
	itemLevel: number,
	rarity: ItemTypes.ItemRarity,
	rng: Random
): { ItemTypes.AffixInstance }
	local budget = AffixRegistry.getAffixBudget(rarity)
	local context = AffixRegistry.getContext(def)
	local out: { ItemTypes.AffixInstance } = {}

	local function rollKind(kind: ItemTypes.AffixKind, count: number)
		if count <= 0 then
			return
		end
		local available = AffixRegistry.listByKindForContext(kind, context, itemLevel)
		for _ = 1, count do
			local pickedDef = weightedPick(available, function(entry)
				return entry.weight
			end, rng)
			if not pickedDef then
				break
			end
			local tier = pickTier(pickedDef, itemLevel, context, rng)
			if tier then
				local label = pickLabel(tier, rng)
				local modDefs = resolveModifierDefs(tier, context)
				local mods: { ItemTypes.ModifierEntry } = {}
				for modIndex, modDef in ipairs(modDefs) do
					table.insert(mods, makeRolledModifier(pickedDef.id, tier.tier, modIndex, modDef, itemLevel, label, rng))
				end
				table.insert(out, {
					id = pickedDef.id,
					kind = kind,
					label = label,
					tier = tier.tier,
					modifiers = mods,
					meta = {
						context = context,
					},
				})
			end
			for i, entry in ipairs(available) do
				if entry == pickedDef then
					table.remove(available, i)
					break
				end
			end
			if #available == 0 then
				break
			end
		end
	end

	rollKind("prefix", budget.prefix)
	rollKind("suffix", budget.suffix)
	return out
end

local function findNameAffixLabel(affixes: { ItemTypes.AffixInstance | ItemTypes.ModifierEntry }?, kind: ItemTypes.AffixKind): string?
	if not affixes then
		return nil
	end
	for _, affix in ipairs(affixes) do
		local anyAffix = affix :: any
		if anyAffix.kind == kind and type(anyAffix.label) == "string" and anyAffix.label ~= "" then
			return anyAffix.label
		end
	end
	return nil
end

function AffixRollService.composeDisplayName(baseName: string, affixes: { ItemTypes.AffixInstance | ItemTypes.ModifierEntry }?): string
	local name = baseName
	local prefix = findNameAffixLabel(affixes, "prefix")
	local suffix = findNameAffixLabel(affixes, "suffix")
	if prefix then
		name = `{prefix} {name}`
	end
	if suffix then
		name = `{name} {suffix}`
	end
	return name
end

-- Roll the named affix for an item, at `tierNumber` or a weighted tier the item qualifies for. Nil
-- with a reason when the affix does not exist, cannot appear on this item, or has no such tier here.
-- For tooling that builds items to order; drops roll through `prepareMeta`.
function AffixRollService.rollNamed(
	def: ItemTypes.ItemDef,
	itemLevel: number,
	affixId: string,
	tierNumber: number?
): (ItemTypes.AffixInstance?, string?)
	local affixDef: ItemTypes.AffixDef? = nil
	for _, candidate in ipairs(AffixRegistry.list()) do
		if candidate.id == affixId then
			affixDef = candidate
			break
		end
	end
	if not affixDef then
		return nil, `unknown affix '{affixId}'`
	end
	local context = AffixRegistry.getContext(def)
	local rng = Random.new()
	local tier: ItemTypes.AffixTierDef? = nil
	if tierNumber then
		for _, candidate in ipairs(affixDef.tiers) do
			if candidate.tier == tierNumber then
				tier = candidate
				break
			end
		end
		if not tier then
			return nil, `affix '{affixId}' has no tier {tierNumber}`
		end
		if not AffixRegistry.tierAppliesToContext(tier, context) then
			return nil, `affix '{affixId}' tier {tierNumber} grants nothing on '{def.id}' ({context})`
		end
	else
		tier = pickTier(affixDef, itemLevel, context, rng)
		if not tier then
			return nil, `affix '{affixId}' cannot roll on '{def.id}' ({context}) at item level {itemLevel}`
		end
	end
	local chosen = tier :: ItemTypes.AffixTierDef
	local label = pickLabel(chosen, rng)
	local mods: { ItemTypes.ModifierEntry } = {}
	for modIndex, modDef in ipairs(resolveModifierDefs(chosen, context)) do
		table.insert(mods, makeRolledModifier(affixDef.id, chosen.tier, modIndex, modDef, itemLevel, label, rng))
	end
	return {
		id = affixDef.id,
		kind = affixDef.kind,
		label = label,
		tier = chosen.tier,
		modifiers = mods,
		meta = {
			context = context,
		},
	}, nil
end

function AffixRollService.prepareMeta(def: ItemTypes.ItemDef, meta: ItemTypes.ItemMeta?): ItemTypes.ItemMeta?
	if def.category ~= "equipment" then
		return meta
	end

	local out = cloneMeta(meta)
	local rng = Random.new()
	local itemLevel = EquipmentDefUtils.resolveInstanceItemLevel(def, out)
	out.itemLevel = itemLevel
	out.rarity = pickRarity(out, def, rng)

	local hasSemanticAffixes = false
	if out.affixes then
		for _, affix in ipairs(out.affixes) do
			local anyAffix = affix :: any
			if type(anyAffix.kind) == "string" and type(anyAffix.label) == "string" then
				hasSemanticAffixes = true
				break
			end
		end
	end

	if (not out.affixes) or (#out.affixes == 0) then
		out.affixes = rollAffixInstances(def, itemLevel, out.rarity :: ItemTypes.ItemRarity, rng)
	elseif not hasSemanticAffixes then
		-- Keep legacy affix format as-is; only semantic affixes contribute to naming.
	end

	out.displayName = AffixRollService.composeDisplayName(def.name, out.affixes)
	return out
end

return AffixRollService
