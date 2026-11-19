-- Placeholder clips. Angles are degrees in the parent part's space:
--   arms: x + raises forward, z + raises the right arm out to the side (- for the left arm),
--         y + sweeps toward the left. The weapon sits at right angles to the fist, pointing where
--         a hanging arm's knuckles face, so its heading in a sideways-raised arm equals the arm's y.
--   Torso (root): y + turns left, x - leans forward.
-- Clips pose the upper body only: a pose on a leg would override the walk cycle, and attacks are
-- made on the move. Contact keyframes sit where the profile's hitDelays fall in its stepDurations
-- (about half way), since playback is rescaled to the step duration.
local UPPER = { "Torso", "Head", "Right Arm", "Left Arm" }

local SWORD_GUARD = {
	Torso = { 0, -12, 0 },
	Head = { 0, 10, 0 },
	["Right Arm"] = { 32, 18, 14 },
	["Left Arm"] = { 18, 0, -14 },
}

local DAGGER_GUARD = {
	Torso = { 0, -18, 0 },
	Head = { 0, 14, 0 },
	["Right Arm"] = { 22, 8, 10 },
	["Left Arm"] = { 38, -10, -12 },
}

local function breathe(guard, amount)
	local out = {}
	for part, spec in guard do
		out[part] = { spec[1], spec[2], spec[3] }
	end
	out["Right Arm"][1] += amount
	out["Left Arm"][1] += amount * 0.8
	out.Torso[1] += amount * 0.25
	return out
end

local clips = {}

clips["sword_light_1h/idle"] = {
	loop = true,
	parts = UPPER,
	keys = {
		{ t = 0, ease = "inout", poses = SWORD_GUARD },
		{ t = 1, ease = "inout", poses = breathe(SWORD_GUARD, 3) },
		{ t = 2, ease = "inout", poses = SWORD_GUARD },
	},
}

-- Forehand: a descending cut from the right, carried by the torso turning through it.
clips["sword_light_1h/slash_1"] = {
	parts = UPPER,
	keys = {
		{ t = 0, ease = "out", poses = SWORD_GUARD },
		{ t = 0.17, ease = "inn", poses = {
			Torso = { 4, -28, 0 },
			Head = { 0, 22, 0 },
			["Right Arm"] = { 0, -50, 105 },
			["Left Arm"] = { 35, 0, -20 },
		} },
		{ t = 0.26, ease = "out", marker = "Hit", poses = {
			Torso = { -4, 6, 0 },
			Head = { 0, -4, 0 },
			["Right Arm"] = { 0, 4, 88 },
			["Left Arm"] = { -10, 0, -18 },
		} },
		{ t = 0.36, ease = "inout", poses = {
			Torso = { -6, 26, 0 },
			Head = { 0, -16, 0 },
			["Right Arm"] = { 0, 62, 72 },
			["Left Arm"] = { -30, 0, -22 },
		} },
		{ t = 0.5, ease = "inout", poses = SWORD_GUARD },
	},
}

-- Backhand: from across the chest back out to the right, rising slightly.
clips["sword_light_1h/slash_2"] = {
	parts = UPPER,
	keys = {
		{ t = 0, ease = "out", poses = SWORD_GUARD },
		{ t = 0.17, ease = "inn", poses = {
			Torso = { 2, 30, 0 },
			Head = { 0, -20, 0 },
			["Right Arm"] = { 0, 100, 78 },
			["Left Arm"] = { -25, 0, -25 },
		} },
		{ t = 0.26, ease = "out", marker = "Hit", poses = {
			Torso = { -4, 0, 0 },
			Head = { 0, 0, 0 },
			["Right Arm"] = { 0, 2, 92 },
			["Left Arm"] = { 15, 0, -18 },
		} },
		{ t = 0.36, ease = "inout", poses = {
			Torso = { -4, -24, 0 },
			Head = { 0, 16, 0 },
			["Right Arm"] = { 0, -45, 110 },
			["Left Arm"] = { 35, 0, -20 },
		} },
		{ t = 0.5, ease = "inout", poses = SWORD_GUARD },
	},
}

-- Two-handed overhead chop: the blade goes behind the head, then down in front with a lean in.
clips["sword_light_1h/heavy_3"] = {
	parts = UPPER,
	keys = {
		{ t = 0, ease = "out", poses = SWORD_GUARD },
		{ t = 0.24, ease = "inn", poses = {
			Torso = { 8, -6, 0 },
			Head = { -8, 4, 0 },
			["Right Arm"] = { 192, 0, 8 },
			["Left Arm"] = { 180, 0, -12 },
		} },
		{ t = 0.36, ease = "out", marker = "Hit", poses = {
			Torso = { -12, 2, 0, offset = Vector3.new(0, 0, -0.35) },
			Head = { 10, 0, 0 },
			["Right Arm"] = { 28, 0, 6 },
			["Left Arm"] = { 40, 0, -20 },
		} },
		{ t = 0.46, ease = "inout", poses = {
			Torso = { -14, 2, 0, offset = Vector3.new(0, 0, -0.35) },
			Head = { 12, 0, 0 },
			["Right Arm"] = { 6, 0, 8 },
			["Left Arm"] = { 22, 0, -20 },
		} },
		{ t = 0.65, ease = "inout", poses = SWORD_GUARD },
	},
}

clips["dagger_light_1h/idle"] = {
	loop = true,
	parts = UPPER,
	keys = {
		{ t = 0, ease = "inout", poses = DAGGER_GUARD },
		{ t = 0.8, ease = "inout", poses = breathe(DAGGER_GUARD, 3) },
		{ t = 1.6, ease = "inout", poses = DAGGER_GUARD },
	},
}

-- Low thrust: the fist drives forward from the hip and the body lunges after it.
clips["dagger_light_1h/stab_1"] = {
	parts = UPPER,
	keys = {
		{ t = 0, ease = "out", poses = DAGGER_GUARD },
		{ t = 0.12, ease = "inn", poses = {
			Torso = { 2, -30, 0 },
			Head = { 0, 24, 0 },
			["Right Arm"] = { -30, 0, 12 },
			["Left Arm"] = { 45, -10, -10 },
		} },
		{ t = 0.175, ease = "out", marker = "Hit", poses = {
			Torso = { -8, 10, 0, offset = Vector3.new(0, 0, -0.4) },
			Head = { 6, -8, 0 },
			["Right Arm"] = { 34, 12, 4 },
			["Left Arm"] = { -15, 0, -14 },
		} },
		{ t = 0.24, ease = "inout", poses = {
			Torso = { -8, 12, 0, offset = Vector3.new(0, 0, -0.4) },
			Head = { 6, -10, 0 },
			["Right Arm"] = { 38, 14, 4 },
			["Left Arm"] = { -18, 0, -14 },
		} },
		{ t = 0.35, ease = "inout", poses = DAGGER_GUARD },
	},
}

-- Second thrust, higher and turned harder through the shoulders.
clips["dagger_light_1h/stab_2"] = {
	parts = UPPER,
	keys = {
		{ t = 0, ease = "out", poses = DAGGER_GUARD },
		{ t = 0.12, ease = "inn", poses = {
			Torso = { 0, -38, 0 },
			Head = { 0, 30, 0 },
			["Right Arm"] = { -10, 0, 30 },
			["Left Arm"] = { 55, -15, -10 },
		} },
		{ t = 0.175, ease = "out", marker = "Hit", poses = {
			Torso = { -6, 22, 0, offset = Vector3.new(0, 0, -0.5) },
			Head = { 4, -18, 0 },
			["Right Arm"] = { 55, 20, 8 },
			["Left Arm"] = { -20, 0, -16 },
		} },
		{ t = 0.24, ease = "inout", poses = {
			Torso = { -6, 24, 0, offset = Vector3.new(0, 0, -0.5) },
			Head = { 4, -20, 0 },
			["Right Arm"] = { 58, 22, 8 },
			["Left Arm"] = { -22, 0, -16 },
		} },
		{ t = 0.35, ease = "inout", poses = DAGGER_GUARD },
	},
}

-- Rising diagonal slash to close the chain.
clips["dagger_light_1h/slash_3"] = {
	parts = UPPER,
	keys = {
		{ t = 0, ease = "out", poses = DAGGER_GUARD },
		{ t = 0.13, ease = "inn", poses = {
			Torso = { 2, -32, 0 },
			Head = { 0, 26, 0 },
			["Right Arm"] = { 0, -45, 45 },
			["Left Arm"] = { 40, -10, -15 },
		} },
		{ t = 0.21, ease = "out", marker = "Hit", poses = {
			Torso = { -4, 6, 0, offset = Vector3.new(0, 0, -0.3) },
			Head = { 0, -4, 0 },
			["Right Arm"] = { 0, 4, 85 },
			["Left Arm"] = { -10, 0, -18 },
		} },
		{ t = 0.29, ease = "inout", poses = {
			Torso = { -4, 30, 0, offset = Vector3.new(0, 0, -0.3) },
			Head = { 0, -20, 0 },
			["Right Arm"] = { 0, 65, 125 },
			["Left Arm"] = { -30, 0, -22 },
		} },
		{ t = 0.4, ease = "inout", poses = DAGGER_GUARD },
	},
}

return clips
