--!strict
-- Client-facing visual spec per skill (animations/FX/SFX keys)
-- Keys must match assets under ReplicatedStorage/Assets

local ClientSpec = {
	Punch = {
		class = "BasicComboSkill",
		icon = "rbxassetid://13050670424",
		label = "Punch",
		anim = {
			-- Body animations for each combo step in order
			comboSteps = {
				{ key = "Punch_Combo_1" },
				{ key = "Punch_Combo_2" },
				{ key = "Punch_Combo_3" },
			},
			-- Note: FX/SFX per impact are still configured under fx/sfx.impact below.
			comboIdle = "Punch_Idle", -- optional idle during combo wait
		},
		fx = {
			-- Default anchor for step/marker FX (optional)
			anchor = { name = "FX_Hand_R", fallback = "RightHand" },
			-- Optional per-step anchors (1-indexed to comboSteps)
			-- Example: step 2 is a left hook, so attach FX to left hand
			anchorsByStep = {
				[2] = { name = "FX_Hand_L", fallback = "LeftHand" },
			},
			-- Marker-driven FX: map animation marker name -> FX behavior
			-- - play (default): play one-shot FX
			-- - start: spawn looping/long-lived FX (will keep running until a matching 'stop')
			-- - stop: stop a previously started FX of the same key
			-- Multiple different animations (combo steps) can share the same marker names.
			markers = {
				-- Windup looper starts
				punch_windup_start = { key = "Punch_Windup", action = "start" },
				-- Windup looper ends
				punch_windup_end = { key = "Punch_Windup", action = "stop" },
				-- Impact one-shot
				Punch_Land = "Punch_Land",
			},
		},
		sfx = {
			impact = { "Punch_Hit_SFX" },
		},
	},

	TripleStrike = {
		class = "BasicSkill",
		icon = "rbxassetid://13050670424",
		label = "Triple",
		anim = {
			start = { key = "TripleStrike_Start" },
			finish = { key = "TripleStrike_End" },
		},
		fx = {
			-- impact list aligns by step index: 1,2,3
			impact = { "TS_Impact_1", "TS_Impact_2", "TS_Impact_3" },
		},
		sfx = {
			impact = { "TS_Hit_1", "TS_Hit_2", "TS_Hit_3" },
		},
	},

	Dash = {
		class = "BasicSkill",
		icon = "rbxassetid://13050670424",
		label = "Dash",
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
	},

	ManaBall = {
		class = "BasicSkill",
		icon = "rbxassetid://13050670424",
		label = "Mana Ball",
		anim = {
			start = { key = "SpellCast_Basic" },
		},
		fx = {
			release = "release",
		},
	},
}

return ClientSpec
