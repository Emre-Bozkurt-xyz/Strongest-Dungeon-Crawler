--!strict
local Types = require(game:GetService("ReplicatedStorage").Shared.skills.SkillSpecTypes)

local data: Types.ServerSkillConfig = {
	name = "DodgeRoll",
	tags = { "traversal" },
	description = "The basic dodge roll maneuver.",
	cooldown = 1,
	gcd = 0.05,
	level = 1,
	cost = 15,
	distance = 12,
	baseResource = "Stamina",
	baseDuration = 0.5,
	invulnerabilityDuration = 0.4,
	animCategory = "dodgeRoll",
}

return data
