--!strict
-- Derives the ItemInspectPanel view model from raw inventory/item data.
--
-- Pure: takes state in, returns a plain table. Keeping this out of the component makes the display
-- rules testable and reusable -- the same model will feed the hover tooltip if R14 goes ahead.
--
-- The old runtime flattened everything into one list of pre-formatted strings, which is why it had
-- no hierarchy. This returns grouped, still-structured data and lets the component decide how to
-- present it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)
local Registry = require(ReplicatedStorage.Shared.items.Registry)
local EquipmentDefUtils = require(ReplicatedStorage.Shared.items.EquipmentDefUtils)

local Selector = {}

export type ItemLocation = {
	container: "inventory" | "equipment",
	slot: any,
}

export type RequirementRow = {
	label: string,
	required: number,
	current: number?,
	-- nil when the value cannot be read on the client, so the row renders neutrally rather than
	-- claiming a pass or a failure it cannot know.
	met: boolean?,
}

export type WeaponDamageRow = {
	damageType: ItemTypes.DamageType,
	min: number,
	max: number,
}

export type WeaponView = {
	class: ItemTypes.WeaponClass,
	handedness: ItemTypes.WeaponHandedness,
	damages: { WeaponDamageRow },
	attackSpeed: number,
	critChance: number?,
	range: number?,
}

export type ModifierRow = {
	label: string,
	value: string,
}

export type ChargesView = {
	current: number,
	max: number?,
}

export type InspectView = {
	found: boolean,
	displayName: string,
	icon: string,
	rarity: string,
	itemLevel: number?,
	isEquipment: boolean,
	weapon: WeaponView?,
	charges: ChargesView?,
	requirements: { RequirementRow },
	baseStats: { ModifierRow },
	affixes: { ModifierRow },
}

local function formatNumber(value: number): string
	if math.abs(value - math.floor(value + 0.5)) < 1e-6 then
		return tostring(math.floor(value + 0.5))
	end
	return string.format("%.2f", value)
end

local function formatModifierValue(mod: ItemTypes.ModifierEntry): string
	if mod.kind == "percent" then
		return `+{formatNumber(mod.value * 100)}%`
	end
	local sign = if mod.value < 0 then "" else "+"
	return `{sign}{formatNumber(mod.value)}`
end

function Selector.getItemLocation(
	uid: string,
	inventory: ItemTypes.InventoryState?,
	equipment: ItemTypes.EquipmentState?
): ItemLocation?
	if inventory then
		for slot, slotUid in pairs(inventory.slots) do
			if slotUid == uid then
				return { container = "inventory", slot = slot }
			end
		end
	end
	if equipment then
		for slot, slotUid in pairs(equipment.slots) do
			if slotUid == uid then
				return { container = "equipment", slot = slot }
			end
		end
	end
	return nil
end

local function buildRequirements(
	def: ItemTypes.ItemDef,
	attributes: any?
): { RequirementRow }
	local rows: { RequirementRow } = {}
	local requirements = EquipmentDefUtils.getRequirements(def)
	if not requirements then
		return rows
	end

	if requirements.level then
		-- No progression system exists yet (D5 in the equipment doc), so this is informational.
		table.insert(rows, { label = "Level", required = requirements.level, current = nil, met = nil })
	end

	if requirements.attributes then
		for name, required in pairs(requirements.attributes) do
			local entry = attributes and (attributes :: any)[name]
			local current = if type(entry) == "table" then entry.current else nil
			table.insert(rows, {
				label = name,
				required = required,
				current = current,
				met = if current ~= nil then current >= required else nil,
			})
		end
	end

	if requirements.stats then
		for name, required in pairs(requirements.stats) do
			-- ClientStatsStore exposes pools only, not static stats, so these cannot be evaluated
			-- client-side. Rendered neutrally rather than guessed.
			table.insert(rows, { label = name, required = required, current = nil, met = nil })
		end
	end

	return rows
end

local function buildWeapon(def: ItemTypes.ItemDef): WeaponView?
	local weapon = EquipmentDefUtils.getWeapon(def)
	if not weapon then
		return nil
	end

	local damages: { WeaponDamageRow } = {}
	for _, range in ipairs(weapon.damage) do
		table.insert(damages, { damageType = range.type, min = range.min, max = range.max })
	end

	return {
		class = weapon.class,
		handedness = weapon.handedness,
		damages = damages,
		attackSpeed = weapon.base.attackSpeed,
		critChance = weapon.base.critChance,
		range = weapon.base.range,
	}
end

local function buildAffixRows(item: ItemTypes.ItemInstance?): { ModifierRow }
	local rows: { ModifierRow } = {}
	local meta = item and item.meta or nil
	local affixes = meta and meta.affixes
	if not affixes then
		return rows
	end

	for _, affix in ipairs(affixes) do
		local anyAffix = affix :: any
		if type(anyAffix) == "table" and anyAffix.modifiers then
			for _, mod in ipairs(anyAffix.modifiers) do
				table.insert(rows, { label = mod.target, value = formatModifierValue(mod) })
			end
		elseif anyAffix.target then
			local mod = anyAffix :: ItemTypes.ModifierEntry
			table.insert(rows, { label = mod.target, value = formatModifierValue(mod) })
		end
	end
	return rows
end

function Selector.buildView(
	item: ItemTypes.ItemInstance?,
	attributes: any?
): InspectView
	local def = item and Registry.get(item.itemId) or nil
	if not def or not item then
		return {
			found = false,
			displayName = "",
			icon = "",
			rarity = "",
			itemLevel = nil,
			isEquipment = false,
			weapon = nil,
			charges = nil,
			requirements = {},
			baseStats = {},
			affixes = {},
		}
	end

	local meta = item.meta

	-- Charges were only ever visible through the old panel's generic meta dump. That dump is
	-- dropped, so anything in it that a player actually needs becomes an explicit field.
	local charges: ChargesView? = nil
	if meta and type(meta.chargesCurrent) == "number" then
		charges = {
			current = meta.chargesCurrent,
			max = if type(meta.chargesMax) == "number" then meta.chargesMax else nil,
		}
	end

	local baseStats: { ModifierRow } = {}
	for _, entry in ipairs(EquipmentDefUtils.getBaseModifiers(def, item)) do
		table.insert(baseStats, { label = entry.target, value = formatModifierValue(entry) })
	end

	return {
		found = true,
		displayName = if meta and type(meta.displayName) == "string" then meta.displayName else def.name,
		icon = def.icon or "",
		rarity = if meta and type(meta.rarity) == "string" then meta.rarity else (def.rarity or "normal"),
		itemLevel = if meta and type(meta.itemLevel) == "number" then meta.itemLevel else nil,
		isEquipment = EquipmentDefUtils.isEquipment(def),
		weapon = buildWeapon(def),
		charges = charges,
		requirements = buildRequirements(def, attributes),
		baseStats = baseStats,
		affixes = buildAffixRows(item),
	}
end

return Selector
