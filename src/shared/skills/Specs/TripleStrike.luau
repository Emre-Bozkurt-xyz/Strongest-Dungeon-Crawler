--!strict
-- Client-facing visual spec for TripleStrike

local Types = require(script.Parent.Parent.SkillSpecTypes)

local spec: Types.SkillSpec = {
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
	-- Read by the server's TripleStrike as well, so its damage and the client's predicted impacts
	-- come from one timeline.
	hits = {
		{ t = 0.10, yaw = 0, coneAngle = 50, coneRange = 8, damageMult = 1.2 },
		{ t = 0.25, yaw = -25, coneAngle = 50, coneRange = 8, damageMult = 0.9 },
		{ t = 0.40, yaw = 25, coneAngle = 50, coneRange = 8, damageMult = 0.9 },
	},
}

return spec
