--!strict
-- Derives the InventoryPanel grid view model: one entry per *held* item matching the active
-- category, in slot order.
--
-- The old runtime rendered a cell for every slot index up to capacity, so the grid was mostly empty
-- boxes and a category filter blanked cells rather than removing them. This returns only what the
-- player actually has, so the grid grows with the inventory and a filter visibly narrows it.
-- `capacity` is still reported for a fullness readout, but it no longer drives how many cells exist.
--
-- The filter rule itself is InventoryMenuRuntime._filterCategory unchanged: "all" bypasses the
-- check, every other category is a straight equality against the item's def.category.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)
local Registry = require(ReplicatedStorage.Shared.items.Registry)

local Selector = {}

export type Category = "all" | ItemTypes.ItemCategory

-- Order and labels the old CategoryBar cloned, plus "All". Kept as one list so the tab strip and the
-- filter agree on what a category even is.
local CATEGORIES: { Category } = { "all", "equipment", "consumable", "material", "quest", "misc" }
Selector.CATEGORIES = CATEGORIES

export type SlotView = {
	key: string,
	slotIndex: number,
	uid: string,
	icon: string?,
	tint: Color3?,
	count: number?,
}

export type InventoryGridView = {
	capacity: number,
	-- How many slots are occupied overall, ignoring the active category, for a "23 / 40" readout.
	used: number,
	slots: { SlotView },
}

-- Not sourced from the theme (Guardrail 3 is about UI chrome, not item data): rarity is a fixed
-- four-value item property, the same table ItemCard.luau and the equipment selector already carry.
local RARITY_TINTS: { [string]: Color3 } = {
	normal = Color3.fromRGB(190, 190, 190),
	magic = Color3.fromRGB(120, 160, 255),
	rare = Color3.fromRGB(240, 210, 110),
	unique = Color3.fromRGB(230, 140, 70),
}

local function itemRarity(item: ItemTypes.ItemInstance, def: ItemTypes.ItemDef?): string?
	if item.meta and type(item.meta.rarity) == "string" then
		return item.meta.rarity
	end
	return def and def.rarity
end

function Selector.matchesCategory(def: ItemTypes.ItemDef, category: Category): boolean
	if category == "all" then
		return true
	end
	return def.category == category
end

function Selector.buildView(
	inventory: ItemTypes.InventoryState?,
	items: { [string]: ItemTypes.ItemInstance },
	category: Category
): InventoryGridView
	local capacity = if inventory then inventory.capacity else 0
	local slots: { SlotView } = {}
	local used = 0

	-- Walked by slot index rather than over `items`, so the order stays stable as things are added
	-- and removed; `pairs` over a uid-keyed map would reshuffle the grid on every change.
	for slotIndex = 1, capacity do
		local uid = inventory and inventory.slots[slotIndex] or nil
		local item = if uid then items[uid] else nil
		local def = if item then Registry.get(item.itemId) else nil
		if not uid or not item or not def then
			continue
		end

		used += 1
		if not Selector.matchesCategory(def, category) then
			continue
		end

		local rarity = itemRarity(item, def)
		table.insert(slots, {
			key = `Slot{slotIndex}`,
			slotIndex = slotIndex,
			uid = uid,
			icon = def.icon,
			tint = if rarity then RARITY_TINTS[rarity] else nil,
			count = if item.stackSize > 1 then item.stackSize else nil,
		})
	end

	return { capacity = capacity, used = used, slots = slots }
end

return Selector
