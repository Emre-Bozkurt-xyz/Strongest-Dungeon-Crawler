--!strict
local data = {
	name = "SinglePunch",
	tags = { "melee", "light" },
	description = "A quick melee strike.",
	cooldown = 1.5,
	gcd = 0.6,
	level = 1,
	animCategory = "melee_light",
	baseDuration = 0.5,
	hits = {
		{
			t = 0.4,
			coneAngle = 55,
			coneRange = 7,
			damageMult = 1.0,
		},
	},
}

return data
