--!strict
-- Derives the WorldLootInspectPanel view model: a title and one row per nearby drop, nearest first.
--
-- Rows stay in LootClient's order (distance, then rarity, then name), so this does no sorting of its
-- own -- the keyboard's up/down walks the same order the panel draws.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Registry = require(ReplicatedStorage.Shared.items.Registry)
local SharedConfig = require(ReplicatedStorage.Shared.Config)
local LootClient = require(script.Parent.Parent.controllers.LootClient)

local Selector = {}

export type RowView = {
	-- The drop's item uid, which is stable while it stays in range, so it doubles as the React key.
	uid: string,
	name: string,
	icon: string?,
	rarity: string,
	count: number?,
	selected: boolean,
}

export type LootListView = {
	title: string,
	-- Shown on the selected row, read from config so a rebind cannot leave the hint lying.
	pickupKey: string,
	rows: { RowView },
}

local PICKUP_KEY = SharedConfig.WorldLootInspect.interaction.pickupKey.Name

function Selector.buildView(snapshot: LootClient.Snapshot): LootListView
	local rows: { RowView } = {}
	for _, entry in ipairs(snapshot.entries) do
		local def = Registry.get(entry.itemId)
		table.insert(rows, {
			uid = entry.uid,
			name = entry.displayName,
			icon = if def and def.icon and def.icon ~= "" then def.icon else nil,
			rarity = entry.rarity or "normal",
			count = if entry.stackSize and entry.stackSize > 1 then entry.stackSize else nil,
			selected = entry.uid == snapshot.selectedUid,
		})
	end

	return {
		title = if #rows > 1 then `LOOT ({#rows})` else "LOOT",
		pickupKey = PICKUP_KEY,
		rows = rows,
	}
end

return Selector
