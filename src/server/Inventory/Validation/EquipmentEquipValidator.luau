--!strict
-- Authoritative equip validation for requirements, slots, and hand conflicts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)
local Registry = require(ReplicatedStorage.Shared.items.Registry)
local EquipmentDefUtils = require(ReplicatedStorage.Shared.items.EquipmentDefUtils)
local RequirementEvaluator = require(script.Parent.Parent.Projection.RequirementEvaluator)

local EquipmentEquipValidator = {}

export type ValidateContext = {
	equipment: ItemTypes.EquipmentState,
	itemGetter: (uid: string) -> ItemTypes.ItemInstance?,
}

-- Phase C (D10): a two-handed equip with the Secondary slot occupied is not a hard reject anymore
-- -- it is a recoverable outcome the caller (InventoryService) can act on by auto-unequipping the
-- occupied Secondary first, as a single atomic operation. `validate` still returns `false` for this
-- case (it is not directly equippable as requested), but callers that care can read `outcome` to
-- tell "no, and here's why" apart from "no, but here's what would make it work".
export type ValidateOutcome = {
	requiresSecondaryUnequip: boolean?,
}

local function contains(list: { ItemTypes.EquipSlot }?, value: string): boolean
	if not list then
		return false
	end
	for _, item in ipairs(list) do
		if item == value then
			return true
		end
	end
	return false
end

local function getEquippedDef(ctx: ValidateContext, slotName: string): ItemTypes.ItemDef?
	local uid = ctx.equipment.slots[slotName]
	if not uid then
		return nil
	end
	local inst = ctx.itemGetter(uid)
	if not inst then
		return nil
	end
	return Registry.get(inst.itemId)
end

local function slotAllowedByItem(def: ItemTypes.ItemDef, targetSlot: string): boolean
	local equipSlots = EquipmentDefUtils.getEquipSlots(def)
	if not contains(equipSlots, targetSlot) then
		return false
	end

	local weapon = EquipmentDefUtils.getWeapon(def)
	if weapon and weapon.allowedSlots and not contains(weapon.allowedSlots, targetSlot) then
		return false
	end

	local offhand = EquipmentDefUtils.getOffhand(def)
	if offhand and offhand.allowedSlots and not contains(offhand.allowedSlots, targetSlot) then
		return false
	end

	return true
end

local function validateHandConflicts(
	def: ItemTypes.ItemDef,
	targetSlot: string,
	ctx: ValidateContext
): (boolean, string?, ValidateOutcome?)
	local weapon = EquipmentDefUtils.getWeapon(def)
	if weapon and weapon.handedness == "two_handed" then
		if targetSlot ~= "Main" then
			return false, "two_handed_requires_main"
		end
		local secondaryUid = ctx.equipment.slots.Secondary
		if secondaryUid then
			-- D10: no longer a hard reject. The caller decides whether to auto-unequip the
			-- occupied Secondary (checking inventory space first) and complete the equip
			-- atomically, or to surface this as a rejection if it chooses not to.
			return false, "needs_secondary_unequip", { requiresSecondaryUnequip = true }
		end
		return true, nil
	end

	if targetSlot == "Secondary" then
		local mainDef = getEquippedDef(ctx, "Main")
		local mainWeapon = mainDef and EquipmentDefUtils.getWeapon(mainDef) or nil
		if mainWeapon and mainWeapon.handedness == "two_handed" then
			return false, "main_weapon_blocks_secondary"
		end
	end

	return true, nil
end

function EquipmentEquipValidator.validate(
	entityId: string,
	inst: ItemTypes.ItemInstance,
	targetSlot: string,
	ctx: ValidateContext
): (boolean, string?, ValidateOutcome?)
	local def = Registry.get(inst.itemId)
	if not def then
		return false, "missing_def"
	end
	if def.category ~= "equipment" or not EquipmentDefUtils.isEquipment(def) then
		return false, "not_equipment"
	end
	if not slotAllowedByItem(def, targetSlot) then
		return false, "invalid_slot"
	end

	local reqOk, reqReason = RequirementEvaluator.evaluate(entityId, def)
	if not reqOk then
		return false, reqReason or "requirements_not_met"
	end

	return validateHandConflicts(def, targetSlot, ctx)
end

return EquipmentEquipValidator
