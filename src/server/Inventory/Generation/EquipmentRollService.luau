--!strict
-- Rolls equipment base modifiers and prepares per-instance equipment meta.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)
local EquipmentDefUtils = require(ReplicatedStorage.Shared.items.EquipmentDefUtils)
local AffixRollService = require(script.Parent.AffixRollService)

local EquipmentRollService = {}

local function cloneMeta(meta: ItemTypes.ItemMeta?): ItemTypes.ItemMeta
	if meta then
		return table.clone(meta)
	end
	return {}
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

local function cloneTags(tags: { string }?): { string }?
	return if tags then table.clone(tags) else nil
end

local function cloneMetaTable(meta: { [string]: any }?): { [string]: any }?
	return if meta then table.clone(meta) else nil
end

local function rollBaseModifier(
	def: ItemTypes.ItemDef,
	rollDef: ItemTypes.EquipmentModifierRollDef,
	itemLevel: number,
	index: number,
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

	local raw = rng:NextNumber(minV, maxV)
	local value = roundValue(raw, isInteger(minV) and isInteger(maxV))
	local meta = cloneMetaTable(rollDef.meta) or {}
	if rollDef.container == "attribute" then
		meta.container = "attribute"
	end

	return {
		id = rollDef.id or `base_roll::{def.id}::{index}`,
		kind = rollDef.kind,
		target = rollDef.target,
		value = value,
		description = rollDef.description or `Base roll from {def.id}`,
		tags = cloneTags(rollDef.tags),
		priority = rollDef.priority,
		meta = if next(meta) ~= nil then meta else nil,
	}
end

function EquipmentRollService.prepareMeta(def: ItemTypes.ItemDef, meta: ItemTypes.ItemMeta?): ItemTypes.ItemMeta?
	if not EquipmentDefUtils.isEquipment(def) then
		return meta
	end

	local out = cloneMeta(meta)
	out = AffixRollService.prepareMeta(def, out) or out

	local baseRolls = EquipmentDefUtils.getBaseRolls(def)
	if baseRolls and (#baseRolls > 0) and (out.baseModifiers == nil or #out.baseModifiers == 0) then
		local rng = Random.new()
		local itemLevel = EquipmentDefUtils.resolveInstanceItemLevel(def, out)
		out.itemLevel = itemLevel
		local rolled: { ItemTypes.ModifierEntry } = {}
		for index, rollDef in ipairs(baseRolls) do
			table.insert(rolled, rollBaseModifier(def, rollDef, itemLevel, index, rng))
		end
		out.baseModifiers = rolled
	end

	return out
end

return EquipmentRollService
