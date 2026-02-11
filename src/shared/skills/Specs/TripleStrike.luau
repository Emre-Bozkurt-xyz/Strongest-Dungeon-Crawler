--!strict
-- Client-facing visual spec for TripleStrike

local Types = require(script.Parent.Parent.SkillSpecTypes)

local spec: Types.BasicSkillSpec = {
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
}

return spec
