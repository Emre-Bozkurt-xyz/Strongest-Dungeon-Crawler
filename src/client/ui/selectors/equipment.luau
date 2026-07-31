--!strict
-- Derives the EquipmentPanel view model: one row per paper-doll socket, plus every
-- equipment-capable inventory item as a candidate the player can equip.
--
-- The candidate list is deliberately NOT filtered down to "items for the selected slot" --
-- EquipmentPanelRuntime never filtered it either (docs/tasks/ui-migration-plan.md's "Reading the
-- Studio exports" led to reading that runtime directly): every equippable inventory item is always
-- a candidate, and the selected slot only decides which socket a click resolves to. Filtering would
-- read as an improvement but is a capability change (Guardrail 1), so it stays exactly as it was.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)
local Registry = require(ReplicatedStorage.Shared.items.Registry)
local EquipmentDefUtils = require(ReplicatedStorage.Shared.items.EquipmentDefUtils)
local EquipmentSlotSchema = require(ReplicatedStorage.Shared.ui.EquipmentSlotSchema)

local Selector = {}

export type EquipSlot = EquipmentSlotSchema.EquipmentSlotId

export type SlotView = {
	slot: EquipSlot,
	uid: string?,
	icon: string?,
	tint: Color3?,
	count: number?,
}

export type CandidateView = {
	-- Unique per inventory slot index; used as the dict key so the grid keys its list (Guardrail 5).
	key: string,
	slotIndex: number,
	uid: string,
	icon: string?,
	tint: Color3?,
	count: number?,
	-- Which socket clicking this candidate equips into: the selected slot when the item accepts it,
	-- else its first compatible slot (mirrors EquipmentPanelRuntime.resolveCandidateTargetSlot).
	targetSlot: EquipSlot,
}

export type EquipmentView = {
	slots: { SlotView },
	candidates: { CandidateView },
}

-- Not sourced from the theme (Guardrail 3 is about UI chrome, not item data): rarity is a fixed
-- four-value item property, the same distinction ItemCard.luau's RARITY_COLORS already draws.
local RARITY_TINTS: { [string]: Color3 } = {
	normal = Color3.fromRGB(190, 190, 190),
	magic = Color3.fromRGB(120, 160, 255),
	rare = Color3.fromRGB(240, 210, 110),
	unique = Color3.fromRGB(230, 140, 70),
}

function Selector.rarityTint(rarity: string?): Color3?
	if not rarity then
		return nil
	end
	return RARITY_TINTS[rarity]
end

local function itemRarity(item: ItemTypes.ItemInstance, def: ItemTypes.ItemDef?): string?
	if item.meta and type(item.meta.rarity) == "string" then
		return item.meta.rarity
	end
	return def and def.rarity
end

local function compatibleSlots(def: ItemTypes.ItemDef): { EquipSlot }
	local out: { EquipSlot } = {}
	if not EquipmentDefUtils.isEquipment(def) then
		return out
	end
	local raw = EquipmentDefUtils.getEquipSlots(def)
	if not raw then
		return out
	end
	for _, rawSlot in ipairs(raw) do
		local canonical = EquipmentSlotSchema.canonicalize(rawSlot)
		if canonical then
			table.insert(out, canonical)
		end
	end
	return out
end

local function resolveTargetSlot(slots: { EquipSlot }, selectedSlot: EquipSlot?): EquipSlot?
	if #slots == 0 then
		return nil
	end
	if selectedSlot then
		for _, slot in ipairs(slots) do
			if slot == selectedSlot then
				return selectedSlot
			end
		end
	end
	return slots[1]
end

function Selector.buildView(
	inventory: ItemTypes.InventoryState?,
	equipment: ItemTypes.EquipmentState?,
	items: { [string]: ItemTypes.ItemInstance },
	selectedSlot: EquipSlot?
): EquipmentView
	local slots: { SlotView } = {}
	for _, slotId in ipairs(EquipmentSlotSchema.list()) do
		local uid = equipment and equipment.slots[slotId] or nil
		local item = if uid then items[uid] else nil
		local def = if item then Registry.get(item.itemId) else nil
		table.insert(slots, {
			slot = slotId,
			uid = uid,
			icon = if def then def.icon else nil,
			tint = Selector.rarityTint(if item then itemRarity(item, def) else nil),
			count = if item and item.stackSize > 1 then item.stackSize else nil,
		})
	end

	local candidates: { CandidateView } = {}
	if inventory then
		for slotIndex = 1, inventory.capacity do
			local uid = inventory.slots[slotIndex]
			local item = if uid then items[uid] else nil
			local def = if item then Registry.get(item.itemId) else nil
			if item and def then
				local target = resolveTargetSlot(compatibleSlots(def), selectedSlot)
				if target then
					table.insert(candidates, {
						key = `Slot{slotIndex}`,
						slotIndex = slotIndex,
						uid = item.uid,
						icon = def.icon,
						tint = Selector.rarityTint(itemRarity(item, def)),
						count = if item.stackSize > 1 then item.stackSize else nil,
						targetSlot = target,
					})
				end
			end
		end
	end

	return { slots = slots, candidates = candidates }
end

return Selector
