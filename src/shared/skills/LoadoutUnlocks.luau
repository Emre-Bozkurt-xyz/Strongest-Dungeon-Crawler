--!strict
-- Which skill slots and slot sets the character has opened (docs/planning/progression-direction.md,
-- "Loadout"): a new character starts with one set of three slots, and more open at character level
-- milestones. The levels are placeholders until pacing is tuned.
--
-- Like the passive slots (PassivePool), the save keeps every slot and set whatever the level; a
-- locked one is inert rather than emptied, so retuning a milestone needs no migration.

local LoadoutTypes = require(script.Parent.LoadoutTypes)

local LoadoutUnlocks = {}

-- The level each slot opens at, by slot index. Ascending, so the open slots are always the first N.
LoadoutUnlocks.SLOT_LEVELS = { 1, 1, 1, 5, 10 }
-- The level each set opens at, by set index.
LoadoutUnlocks.SET_LEVELS = { 1, 15 }

assert(#LoadoutUnlocks.SLOT_LEVELS == LoadoutTypes.SLOTS_PER_SET, "a level for every slot")
assert(#LoadoutUnlocks.SET_LEVELS == LoadoutTypes.MAX_SETS, "a level for every set")

local function countOpen(levels: { number }, level: number): number
	local open = 0
	for _, threshold in ipairs(levels) do
		if level >= threshold then
			open += 1
		end
	end
	return open
end

export type Limits = { slots: number, sets: number }

function LoadoutUnlocks.limitsFor(level: number): Limits
	return {
		slots = countOpen(LoadoutUnlocks.SLOT_LEVELS, level),
		sets = countOpen(LoadoutUnlocks.SET_LEVELS, level),
	}
end

return LoadoutUnlocks
