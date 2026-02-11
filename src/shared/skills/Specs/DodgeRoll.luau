--!strict
-- Client-facing visual spec for Dodge Roll

local Types = require(script.Parent.Parent.SkillSpecTypes)

local spec: Types.DodgeRollSkillSpec = {
	class = "DodgeRollSkill",
	icon = "rbxassetid://13050670424",
	label = "Dodge Roll",
	directional = {
		forward = {
			anim = {
				start = { key = "DodgeRoll" },
			},
			camera = {
				priority = 10,
				followSmoothness = 0.25,
				lookSmoothness = 0.25,
			},
		},
		back = {
			anim = {
				start = { key = "DodgeRoll" },
			},
			camera = {
				priority = 10,
				followSmoothness = 1,
				lookSmoothness = 0.2,
				shoulderBack = 8.0,
				shoulderUp = 3.0,
				lockYaw = true,
			},
		},
		left = {
			anim = {
				start = { key = "DodgeRoll" },
			},
			camera = {
				priority = 10,
				followSmoothness = 0.8,
				lookSmoothness = 0.25,
				lockYaw = true,
			},
		},
		right = {
			anim = {
				start = { key = "DodgeRoll" },
			},
			camera = {
				priority = 10,
				followSmoothness = 0.8,
				lookSmoothness = 0.25,
				lockYaw = true,
			},
		},
	},
	anim = {
		start = { key = "DodgeRoll" },
	},
}

return spec
