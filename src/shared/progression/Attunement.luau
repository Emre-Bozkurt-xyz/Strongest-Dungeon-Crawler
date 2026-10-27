--!strict
-- Attunement: the masteries a character focuses on (docs/planning/progression-direction.md,
-- "Attunement"). It is changed only at an Attunement Shrine in the world, never from a menu.
--
-- What it does is per family (MasteryTree.isActive): an attack-type track gives nothing unattuned
-- but its root form, so anyone can still swing a sword; an element track always works, and
-- attuning it opens its end node (and, once passives exist, strengthens its tree). Unattuning never
-- removes progress, and XP is earned either way.
--
-- What is attuned is saved (`progression.attunement`); how many slots a character has is derived
-- from their level, so retuning a slot level needs no save migration.

local MasteryTracks = require(script.Parent.MasteryTracks)

local Attunement = {}

-- Character levels that open a slot. Placeholders: the first is part of onboarding, the second
-- comes soon after but not with it (progression-launch-content.md, "Milestones").
Attunement.SLOT_LEVELS = { 3, 6 }

-- Instances with this tag are shrines; the server gives each a prompt.
Attunement.SHRINE_TAG = "AttunementShrine"
-- How close to a shrine a player must stand to change attunement, in studs.
Attunement.SHRINE_RANGE = 14

function Attunement.slotsFor(level: number): number
	local slots = 0
	for _, required in ipairs(Attunement.SLOT_LEVELS) do
		if level >= required then
			slots += 1
		end
	end
	return slots
end

-- The level that opens the next slot, or nil when every slot is open.
function Attunement.nextSlotLevel(level: number): number?
	for _, required in ipairs(Attunement.SLOT_LEVELS) do
		if level < required then
			return required
		end
	end
	return nil
end

-- What is attuned in effect: the saved list without unknown or repeated tracks, cut to the slots
-- the level allows (a retuned slot level cannot leave a character over the limit).
function Attunement.effective(saved: { string }?, level: number): { string }
	local out: { string } = {}
	local slots = Attunement.slotsFor(level)
	for _, trackId in ipairs(saved or {}) do
		if #out >= slots then
			break
		end
		if type(trackId) == "string" and MasteryTracks.get(trackId) and not table.find(out, trackId) then
			table.insert(out, trackId)
		end
	end
	return out
end

return Attunement
