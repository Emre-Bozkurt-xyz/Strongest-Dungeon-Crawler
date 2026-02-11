--!strict
local Types = require(game:GetService("ReplicatedStorage").Shared.skills.SkillSpecTypes)

local data: Types.ServerSkillConfig = {
	name = "CascadingManaBalls",
	description = "Fires a flurry of mana balls that cascade toward a target point.",
	cooldown = 4,
	gcd = 0.7,
	level = 1,
	cost = 20,
	baseResource = "Mana",
	baseDuration = 1.25,
	animCategory = "spell_cast",
	tags = { "spell", "projectile" },
	damageMult = 0.25,
	projectileServer = {
		radius = 1.5,
		pierce = 1,
		impact = {
			mode = "explode",
			radius = 6,
			onEnd = true,
		},
	},
}

return data
