local SkillsFolder = script.Parent.Skills

local SkillsConfig = {}

-- minimal skill data; expand as needed
SkillsConfig.skills = {
	Punch = {
		name = "Punch",
		description = "A simple melee attack",
		cooldown = 2.0,
		gcd = 1.0,
		level = 1,
		-- Combo configuration (optional)
		combo = {
			steps = 3, -- left jab, right jab, heavy
			window = 1, -- seconds to press again to advance combo
			stepDelays = { 0.3, 0.6, 0.0 }, -- enforced minimum delay before next press allowed (each within window)
		},
	},
	TripleStrike = {
		name = "TripleStrike",
		description = "Three quick strikes in different arcs",
		cooldown = 6.0,
		gcd = 1.0,
		level = 1,
	},
}

function SkillsConfig.addSkill(player: Player, name: string)
	local skillData = SkillsConfig.skills[name]
	if not skillData then
		error(`Skill '{name}' does not exist in SkillsConfig`)
	end

	local SkillClass = require(SkillsFolder:WaitForChild(name))
	return SkillClass.new(player, skillData)
end

return SkillsConfig
