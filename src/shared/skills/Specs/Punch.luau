--!strict
-- Client-facing visual spec for Punch (animations/FX/SFX keys)

local Types = require(script.Parent.Parent.SkillSpecTypes)

local spec: Types.SkillSpec = {
	class = "BasicComboSkill",
	icon = "rbxassetid://13050670424",
	label = "Punch",
	tags = { "melee", "light" }, -- used for timing prediction
	combo = {
		steps = 3,
		window = 0.6,
		stepDurations = { 0.45, 0.4, 0.5 }, -- base durations per step
	},
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
		-- - isHitMarker: true = triggers immediate hit feedback (flash, sound, shake)
		-- Multiple different animations (combo steps) can share the same marker names.
		markers = {
			-- Windup looper starts
			punch_windup_start = { key = "Punch_Windup", action = "start" },
			-- Windup looper ends
			punch_windup_end = { key = "Punch_Windup", action = "stop" },
			-- Impact one-shot (isHitMarker triggers client-side hit detection)
			Punch_Land = { key = "Punch_Land", isHitMarker = true },
		},
	},
	-- Hit sounds played on impact marker
	hitSounds = { "rbxassetid://9117969584" },
	-- Cast sounds played when skill starts
	castSounds = { "rbxassetid://5835032207" },
	-- Hit detection cone settings
	hitConeAngle = 70,
	hitConeRange = 6,
	sfx = {
		impact = { "Punch_Hit_SFX" },
	},
}

return spec
