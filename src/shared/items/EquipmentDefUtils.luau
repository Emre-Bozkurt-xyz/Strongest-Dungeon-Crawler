--!strict
-- Shared helpers for resolving legacy + new equipment definition fields during migration.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)
local ItemEnums = require(ReplicatedStorage.Shared.items.ItemEnums)

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

function EquipmentDefUtils.getEquipSlots(def: ItemTypes.ItemDef): { ItemTypes.EquipSlot }?
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
	if def.equipment and type(def.equipment.affixContext) == "string" then
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

function EquipmentDefUtils.getWeapon(def: ItemTypes.ItemDef): ItemTypes.WeaponConfig?
	if def.equipment and def.equipment.weapon then
		return def.equipment.weapon
	end
	return nil
end

function EquipmentDefUtils.getOffhand(def: ItemTypes.ItemDef): ItemTypes.OffhandConfig?
	if def.equipment and def.equipment.offhand then
		return def.equipment.offhand
	end
	return nil
end

-- Weapon base damage is a fixed authored range (see D1 in the architecture doc); it is read
-- from the def only. Instance-level variance comes from scope = "weapon" affixes/base modifiers,
-- which CombatLoadoutResolver folds in separately.
function EquipmentDefUtils.getWeaponDamage(def: ItemTypes.ItemDef): { ItemTypes.WeaponDamageRange }
	local weapon = EquipmentDefUtils.getWeapon(def)
	if not weapon then
		return {}
	end

	local out: { ItemTypes.WeaponDamageRange } = {}
	for _, entry in ipairs(weapon.damage) do
		table.insert(out, table.clone(entry))
	end
	return out
end

-- Resolve the effective scope of a modifier entry. `scope` wins when set; otherwise the legacy
-- `meta.container == "attribute"` marker (predates scopes) is honored so existing attribute
-- affixes (e.g. Fury's Strength roll, OfTheFairy's Dexterity/Intelligence rolls) keep landing in
-- attributes. Everything else defaults to "global".
function EquipmentDefUtils.resolveScope(entry: ItemTypes.ModifierEntry): ItemTypes.ModifierScope
	if entry.scope then
		return entry.scope
	end
	if entry.meta and entry.meta.container == "attribute" then
		return "attribute"
	end
	return "global"
end

-- Scopes that project into player-facing capability containers (stats/attributes).
-- "weapon" and "skill" scoped entries are NOT projected; they stay local to their owning item.
--
-- These take `string` rather than `ModifierScope` deliberately. Luau's old solver widens the
-- singleton union to plain `string` once a resolveScope() result crosses a module boundary, so a
-- `ModifierScope` parameter rejects its own resolveScope() output at the call site. Both are pure
-- equality checks, so accepting `string` costs nothing: an unrecognised value simply returns false.
function EquipmentDefUtils.isProjectedScope(scope: string): boolean
	return scope == "global" or scope == "attribute"
end

function EquipmentDefUtils.isWeaponScope(scope: string): boolean
	return scope == "weapon"
end

local DAMAGE_TARGET_SUFFIX = "Damage"

-- Weapon damage targets are named `<Type>Damage` and map onto a weapon's damage ranges by type:
-- "PhysicalDamage" -> "Physical", "MagicDamage" -> "Magic", "FireDamage" -> "Fire".
--
-- The derived prefix is checked against ItemEnums.DamageType rather than trusted, so a target like
-- "ShadowDamage" returns nil instead of creating a phantom damage range nothing downstream
-- understands. Callers surface that as CombatLoadoutResolver's "had no effect" warning.
function EquipmentDefUtils.weaponDamageTypeForTarget(target: string): ItemTypes.DamageType?
	if #target <= #DAMAGE_TARGET_SUFFIX then
		return nil
	end
	if string.sub(target, -#DAMAGE_TARGET_SUFFIX) ~= DAMAGE_TARGET_SUFFIX then
		return nil
	end
	local candidate = string.sub(target, 1, #target - #DAMAGE_TARGET_SUFFIX)
	if not ItemEnums.isDamageType(candidate) then
		return nil
	end
	return candidate :: ItemTypes.DamageType
end

-- Targets that CombatLoadoutResolver can fold into a weapon. Two callers depend on this being one
-- definition: the resolver (to consume them) and EquipmentAuthoringValidator (to reject authored
-- weapon-scoped modifiers that would land on nothing). Keep them in sync by keeping them here.
function EquipmentDefUtils.isWeaponLocalTarget(target: string): boolean
	if EquipmentDefUtils.weaponDamageTypeForTarget(target) ~= nil then
		return true
	end
	return target == "AttackSpeed" or target == "CriticalHitChance"
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
