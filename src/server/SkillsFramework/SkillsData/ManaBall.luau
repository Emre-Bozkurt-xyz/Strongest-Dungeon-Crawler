--!strict
local Types = require(game:GetService("ReplicatedStorage").Shared.skills.SkillSpecTypes)

local data: Types.ServerSkillConfig = {
	name = "ManaBall",
	description = "Fires a basic magic projectile.",
	cooldown = 0.2,
	gcd = 0.5,
	level = 1,
	cost = 10,
	baseResource = "Mana",
	baseDuration = 0.5,
	animCategory = "spell_cast",
	damage = 30,
	projectileServer = {
		radius = 1.5,
		pierce = 1,
	},
}

return data
