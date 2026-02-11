--!strict
-- Client-facing visual spec for ManaBall

local Types = require(script.Parent.Parent.SkillSpecTypes)

local spec: Types.ManaBallSpec = {
	class = "BasicSkill",
	icon = "rbxassetid://13050670424",
	label = "Mana Ball",
	anim = {
		start = { key = "SpellCast_Basic" },
	},
	fx = {
		release = "release",
	},
	projectile = {
		templateKey = "ManaBall",
		attachPart = "FX_Hand_R",
		movementType = "homing",
		launchSpeed = 90,
		lifetime = 3.5,
		radius = 1.5,
		pierce = 1,
		speculativeImpact = true,
		guidance = {
			kind = "homing",
			turnRate = 360,
			maxRange = 120,
		},
		extraData = { impactKey = "ManaBallImpact" },
	},
	targeting = {
		maxRange = 120,
	},
}

return spec
