--!strict
-- Client-facing visual spec for Dash

local Types = require(script.Parent.Parent.SkillSpecTypes)

local spec: Types.DashSkillSpec = {
	class = "DashSkill",
	icon = "rbxassetid://13050670424",
	label = "Dash",
	directional = {
		forward = {
			anim = {
				start = { key = "Dash" },
			},
			fx = {
				anchor = { name = "FX_Waist", fallback = "HumanoidRootPart" },
				markers = {
					dash_explosive = "Dash_Explosive",
					dash_wind = "Dash_Wind",
				},
			},
			camera = {
				priority = 10,
				followSmoothness = 0.1,
				lookSmoothness = 1,
			},
			-- castSounds / hitSounds can be added per-direction if needed.
		},
		back = {
			anim = {
				start = { key = "Dash" },
			},
			fx = {
				anchor = { name = "FX_Waist", fallback = "HumanoidRootPart" },
				markers = {
					dash_explosive = "Dash_Explosive",
					dash_wind = "Dash_Wind",
				},
			},
			camera = {
				priority = 10,
				followSmoothness = 1,
				lookSmoothness = 1,
				shoulderBack = 3.5,
				shoulderUp = 3.0,
				lockYaw = true,
			},
		},
		left = {
			anim = {
				start = { key = "Dash" },
			},
			fx = {
				anchor = { name = "FX_Waist", fallback = "HumanoidRootPart" },
				markers = {
					dash_explosive = "Dash_Explosive",
					dash_wind = "Dash_Wind",
				},
			},
			camera = {
				priority = 10,
				followSmoothness = 1,
				lookSmoothness = 1,
				lockYaw = true,
			},
		},
		right = {
			anim = {
				start = { key = "Dash" },
			},
			fx = {
				anchor = { name = "FX_Waist", fallback = "HumanoidRootPart" },
				markers = {
					dash_explosive = "Dash_Explosive",
					dash_wind = "Dash_Wind",
				},
			},
			camera = {
				priority = 10,
				followSmoothness = 1,
				lookSmoothness = 1,
				lockYaw = true,
			},
		},
	},
	-- Default visuals (fallback)
	anim = {
		start = { key = "Dash" },
	},
	fx = {
		anchor = { name = "FX_Waist", fallback = "HumanoidRootPart" },
		markers = {
			dash_explosive = "Dash_Explosive",
			dash_wind = "Dash_Wind",
		},
	},
	sfx = {
		start = { "Dash_Start_SFX" },
		loop = { "Dash_Loop_SFX" },
		finish = { "Dash_End_SFX" },
	},
}

return spec
