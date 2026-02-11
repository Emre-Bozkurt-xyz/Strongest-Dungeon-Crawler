--!strict
local Types = require(game:GetService("ReplicatedStorage").Shared.skills.SkillSpecTypes)

local data: Types.ServerSkillConfig = {
	name = "Dash",
	tags = { "traversal" },
	description = "A quick dash forward.",
	cooldown = 1,
	gcd = 0.3,
	level = 1,
	cost = 15,
	distance = 20,
	baseResource = "Stamina",
	baseDuration = 0.3,
	animCategory = "dash",
}

return data
