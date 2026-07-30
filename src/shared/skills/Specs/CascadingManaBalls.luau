--!strict
-- Client-facing visual spec for Cascading Mana Balls

local Types = require(script.Parent.Parent.SkillSpecTypes)

local spec: Types.SkillSpec & {
	projectile: Types.ProjectileSpec,
	flurry: Types.FlurrySpec,
	charge: Types.ChargeSpec,
} = {
	class = "CascadingManaBallsSkill",
	icon = "rbxassetid://13050670424",
	label = "Cascading Mana Balls",
	anim = {
		start = { key = "SpellCast_Basic" },
	},
	fx = {
		release = "release",
	},
	flurry = {
		count = 30,
		interval = 0.05,
		jitter = 0.015,
		startDelay = 0.05,
	},
	charge = {
		maxCount = 30,
		interval = 0.06,
		radius = 4.0,
		radiusJitter = 0.2,
		height = 0.6,
		heightJitter = 0.2,
		arcMinDeg = 0,
		arcMaxDeg = 90,
		arcSymmetric = true,
		arcOscAmplitude = 0.25,
		arcOscSpeed = 1.4,
		wobble = 0.4,
		wobbleSpeed = 2.0,
		forwardOffset = 0.0,
		maxRadius = 6,
	},
	targeting = {
		maxRange = 120,
	},
	projectile = {
		templateKey = "ManaBall",
		attachPart = "FX_Hand_R",
		movementType = "arc",
		launchSpeed = 85,
		lifetime = 3.5,
		radius = 1.5,
		pierce = 1,
		speculativeImpact = true,
		extraData = { impactKey = "ManaBallImpact" },
		arc = {
			amplitude = 6.0,
			amplitudeJitter = 0.35,
			orientationMin = 10,
			orientationMax = 70,
			orientationSymmetric = true,
			orientationMode = "outward",
			orientationJitter = 6,
			plane = "vertical",
		},
		pattern = {
			spread = 3.5,
			amplitude = 3.0,
			amplitudeJitter = 0.3,
			frequency = 1.2,
			frequencyJitter = 0.4,
			groupSize = 5,
			verticalBias = 0.25,
			verticalBiasJitter = 0.1,
			phaseJitter = 0.6,
			flightTimeMin = 0.35,
			flightTimeMax = 1.1,
		},
		impact = {
			mode = "explode",
			radius = 6,
			onEnd = true,
		},
	},
}

return spec
