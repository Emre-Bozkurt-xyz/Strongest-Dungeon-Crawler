--!strict
-- Skill bar command sender.
--
-- The one place a component may reach into SkillSlots to fire a skill (R10), matching how
-- ItemActions is the only door onto inventory commands. SkillSlotButton calls this rather than
-- requiring SkillSlots directly.

local SkillSlots = require(script.Parent.Parent.Parent.SkillsFramework.SkillSlots)

local SkillActions = {}

function SkillActions.activate(slotIndex: number)
	SkillSlots.activate(slotIndex)
end

return SkillActions
