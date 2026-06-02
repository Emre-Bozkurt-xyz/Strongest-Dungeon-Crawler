--!strict
-- Shared helpers for resolving legacy + new equipment definition fields during migration.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)

local EquipmentDefUtils = {}

local function cloneModifier(entry: ItemTypes.ModifierEntry): ItemTypes.ModifierEntry
	local cloned = table.clone(entry)
	if entry.tags then
		cloned.tags = table.clone(entry.tags)
	end
	if entry.meta then
		cloned.meta = table.clone(entry.meta)
	end
	return cloned
end

function EquipmentDefUtils.isEquipment(def: ItemTypes.ItemDef): boolean
	if def.equipment ~= nil then
		return true
	end
	if def.category == "equipment" then
		return true
	end
	return def.equipSlots ~= nil and #def.equipSlots > 0
end

function EquipmentDefUtils.getEquipSlots(def: ItemTypes.ItemDef): { string }?
	if def.equipment and def.equipment.slots then
		return def.equipment.slots
	end
	return def.equipSlots
end

function EquipmentDefUtils.getRequirements(def: ItemTypes.ItemDef): ItemTypes.EquipmentRequirements?
	if def.equipment and def.equipment.requirements then
		return def.equipment.requirements
	end
	return (def.requirements :: any) :: ItemTypes.EquipmentRequirements?
end

function EquipmentDefUtils.getVisualProfileId(def: ItemTypes.ItemDef): string?
	if def.equipment and type(def.equipment.visualProfileId) == "string" and def.equipment.visualProfileId ~= "" then
		return def.equipment.visualProfileId
	end
	return nil
end

function EquipmentDefUtils.getAffixContext(def: ItemTypes.ItemDef): string?
	if def.equipment and type(def.equipment.affixContext) == "string" and def.equipment.affixContext ~= "" then
		return def.equipment.affixContext
	end
	return nil
end

function EquipmentDefUtils.getBaseRolls(def: ItemTypes.ItemDef): { ItemTypes.EquipmentModifierRollDef }?
	if def.equipment and def.equipment.baseRolls then
		return def.equipment.baseRolls
	end
	return nil
end

function EquipmentDefUtils.getBaseItemLevel(def: ItemTypes.ItemDef): number
	local level = def.equipment and def.equipment.itemLevel or nil
	if type(level) == "number" and level > 0 then
		return math.max(1, math.floor(level + 0.5))
	end
	return 1
end

function EquipmentDefUtils.resolveInstanceItemLevel(def: ItemTypes.ItemDef, meta: ItemTypes.ItemMeta?): number
	if meta and type(meta.itemLevel) == "number" and meta.itemLevel > 0 then
		return math.max(1, math.floor(meta.itemLevel + 0.5))
	end
	return EquipmentDefUtils.getBaseItemLevel(def)
end

function EquipmentDefUtils.getCapabilities(def: ItemTypes.ItemDef): ItemTypes.ItemCapability?
	local equipmentCaps = def.equipment and def.equipment.capabilities or nil
	if equipmentCaps and def.capabilities then
		return {
			stats = equipmentCaps.stats or def.capabilities.stats,
			attributes = equipmentCaps.attributes or def.capabilities.attributes,
			skills = equipmentCaps.skills or def.capabilities.skills,
			animationOverrides = equipmentCaps.animationOverrides or def.capabilities.animationOverrides,
		}
	end
	return equipmentCaps or def.capabilities
end

function EquipmentDefUtils.getBaseModifiers(
	def: ItemTypes.ItemDef,
	item: ItemTypes.ItemInstance?
): { ItemTypes.ModifierEntry }
	local out: { ItemTypes.ModifierEntry } = {}

	local meta = item and item.meta or nil
	local rolled = meta and meta.baseModifiers or nil
	if type(rolled) == "table" then
		for _, entry in ipairs(rolled) do
			if type(entry) == "table" and type(entry.target) == "string" and type(entry.value) == "number" then
				table.insert(out, cloneModifier(entry :: ItemTypes.ModifierEntry))
			end
		end
		if #out > 0 then
			return out
		end
	end

	if def.baseStats then
		for statName, value in pairs(def.baseStats) do
			table.insert(out, {
				id = `legacy_base::{statName}`,
				kind = "flat",
				target = statName,
				value = value,
				description = `Base stat from {def.id}`,
			})
		end
	end

	return out
end

return EquipmentDefUtils
