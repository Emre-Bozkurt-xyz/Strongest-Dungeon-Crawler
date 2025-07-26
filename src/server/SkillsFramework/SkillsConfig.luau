local SkillsFolder = script.Parent.Skills

local SkillsConfig = {}

SkillsConfig.skills = {
	Punch = {
		name = "Punch",
		description = "A basic punch attack.",
		cooldown = 1,
	},
}

function SkillsConfig.addSkill(player: Player, name: string)
	local skillData = SkillsConfig.skills[name]
	if not skillData then
		error(`Skill '{name}' does not exist in SkillsConfig`)
	end

	local SkillClass = require(SkillsFolder[name])
	return SkillClass.new(player, skillData)
end

return SkillsConfig
