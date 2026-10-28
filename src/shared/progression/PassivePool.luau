--!strict
-- The selectable passive pool (progression-direction.md, "Node kinds"): stronger, playstyle-specific
-- passives a character chooses up to N of, from every tree at once, so choices from both attuned
-- tracks compete for the same slots.
--
-- Slots open at character level milestones (progression-launch-content.md, "Milestones";
-- placeholders). The saved choice is cut to the slots the level allows, so retuning a milestone
-- needs no migration.

local PassivePool = {}

PassivePool.SLOT_LEVELS = { 10, 25, 50 }

function PassivePool.slotsFor(level: number): number
	local slots = 0
	for _, threshold in ipairs(PassivePool.SLOT_LEVELS) do
		if level >= threshold then
			slots += 1
		end
	end
	return slots
end

return PassivePool
