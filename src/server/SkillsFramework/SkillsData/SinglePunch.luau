--!strict
local data = {
	name = "SinglePunch",
    tags = {"melee", "light"},
	description = "A quick melee strike.",
	cooldown = 1.5,
	gcd = 0.6,
	level = 1,
	animCategory = "melee_light",
	hits = {
		{
			t = 0.18,
			coneAngle = 55,
			coneRange = 7,
			damageMult = 1.0,
		},
	},
}

return data
