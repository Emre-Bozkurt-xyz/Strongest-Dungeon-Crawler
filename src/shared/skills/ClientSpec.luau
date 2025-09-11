--!strict
-- Client-facing visual spec per skill (animations/FX/SFX keys)
-- Keys must match assets under ReplicatedStorage/Assets

local ClientSpec = {
	Punch = {
		icon = "rbxassetid://0", -- TODO: replace
		label = "Punch",
		anim = {
			impact = { "Punch_Combo_1", "Punch_Combo_2", "Punch_Combo_3" }, -- per step impact anims
			comboIdle = "Punch_Idle", -- optional idle during combo wait
		},
		fx = {
			impact = { "Punch_Hit" },
		},
		sfx = {
			impact = { "Punch_Hit_SFX" },
		},
	},

	TripleStrike = {
		icon = "rbxassetid://0",
		label = "Triple",
		anim = {
			start = "TripleStrike_Start",
			finish = "TripleStrike_End",
		},
		fx = {
			-- impact list aligns by step index: 1,2,3
			impact = { "TS_Impact_1", "TS_Impact_2", "TS_Impact_3" },
		},
		sfx = {
			impact = { "TS_Hit_1", "TS_Hit_2", "TS_Hit_3" },
		},
	},
}

return ClientSpec
