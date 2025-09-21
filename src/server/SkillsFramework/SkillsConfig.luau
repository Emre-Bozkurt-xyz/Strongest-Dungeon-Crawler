local SkillsFolder = script.Parent.Skills

local SkillsConfig = {}

export type SkillData = {
	name: string,
	description: string,
	cooldown: number,
	gcd: number,
	level: number,
	combo: {
		steps: number,
		window: number,
		stepDelays: { number }?,
		hitDelays: { number }?,
	}?,
	hits: { {
		t: number,
		yaw: number,
		coneAngle: number,
		coneRange: number,
		playersOnly: boolean?,
		damageMult: number?,
	} }?,
}

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
			-- Optional server hit timings per step (sec from step start to apply damage/impact)
			-- If omitted, defaults to 0 for all steps
			hitDelays = { 0.3, 0.35, 0.35 },
		},
	},
	TripleStrike = {
		name = "TripleStrike",
		description = "Three quick strikes in different arcs",
		cooldown = 6.0,
		gcd = 1.0,
		level = 1,
		-- Optional per-cast hit sequence (non-combo skills)
		hits = {
			{ t = 0.10, yaw = 0,   coneAngle = 50, coneRange = 8, playersOnly = true, damageMult = 0.8 },
			{ t = 0.25, yaw = -25, coneAngle = 50, coneRange = 8, playersOnly = true, damageMult = 1.0 },
			{ t = 0.40, yaw = 25,  coneAngle = 50, coneRange = 8, playersOnly = true, damageMult = 1.2 },
		},
	},
} :: { [string]: SkillData }

function SkillsConfig.addSkill(player: Player, name: string)
	local skillData = SkillsConfig.skills[name]
	if not skillData then
		error(`Skill '{name}' does not exist in SkillsConfig`)
	end

	local SkillClass = require(SkillsFolder:WaitForChild(name))
	return SkillClass.new(player, skillData)
end

return SkillsConfig
