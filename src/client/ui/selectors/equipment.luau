--!strict
-- Derives the EquipmentPanel view model: one row per paper-doll socket, plus every
-- equipment-capable inventory item as a candidate the player can equip.
--
-- The candidate list is deliberately NOT filtered down to "items for the selected slot": every
-- equippable inventory item is always a candidate, and the selected slot only decides which socket a
-- click resolves to. Filtering would read as an improvement but is a capability change (Guardrail 1).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)
local Registry = require(ReplicatedStorage.Shared.items.Registry)
local ItemGlyphs = require(script.Parent.Parent.glyphs.ItemGlyphs)
local EquipmentDefUtils = require(ReplicatedStorage.Shared.items.EquipmentDefUtils)
local EquipmentSlotSchema = require(ReplicatedStorage.Shared.ui.EquipmentSlotSchema)

local Selector = {}

export type EquipSlot = EquipmentSlotSchema.EquipmentSlotId

export type SlotView = {
	slot: EquipSlot,
	uid: string?,
	icon: string?,
	-- ItemGlyphs id, the stand-in while items have no icons.
	glyph: string?,
	rarity: string?,
	count: number?,
}

export type CandidateView = {
	-- Unique per inventory slot index; used as the dict key so the grid keys its list (Guardrail 5).
	key: string,
	slotIndex: number,
	uid: string,
	icon: string?,
	-- ItemGlyphs id, the stand-in while items have no icons.
	glyph: string?,
	rarity: string?,
	count: number?,
	-- Which socket clicking this candidate equips into: the selected slot when the item accepts it,
	-- else its first compatible slot.
	targetSlot: EquipSlot,
}

export type EquipmentView = {
	slots: { SlotView },
	candidates: { CandidateView },
}

-- Every item has a rarity for display; one that declares none is "normal", so a filled slot never
-- renders as empty.
local function itemRarity(item: ItemTypes.ItemInstance, def: ItemTypes.ItemDef?): string
	if item.meta and type(item.meta.rarity) == "string" then
		return item.meta.rarity
	end
	return def and def.rarity or "normal"
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
			glyph = if def then ItemGlyphs.forDef(def) else nil,
			rarity = if item then itemRarity(item, def) else nil,
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
						glyph = ItemGlyphs.forDef(def),
						rarity = itemRarity(item, def),
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
