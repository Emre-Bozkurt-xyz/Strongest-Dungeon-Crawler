--!strict
-- Client-facing visual spec for the adaptive BasicAttack skill.
--
-- Unlike the other combo specs, `anim.comboSteps` is intentionally NOT set here: BasicComboSkill
-- reads `adaptiveBasicAttack` and resolves the actual per-step animations/timing from
-- BasicAttackProfileRegistry (via CombatLoadoutMirror) instead of hardcoding them, so the same
-- keybind plays the unarmed combo or the current weapon's combo depending on what's equipped
-- (D6 in docs/tasks/equipment-item-architecture.md). `combo` below is a static fallback only, used
-- if profile resolution somehow fails.

local Types = require(script.Parent.Parent.SkillSpecTypes)

local spec: Types.SkillSpec = {
	class = "BasicComboSkill",
	icon = "rbxassetid://13050670424",
	label = "Basic Attack",
	tags = { "melee", "light" }, -- used for timing prediction
	adaptiveBasicAttack = true,
	combo = {
		steps = 3,
		window = 0.6,
		stepDurations = { 0.45, 0.4, 0.5 },
	},
	fx = {
		-- Default anchor for step/marker FX (optional)
		anchor = { name = "FX_Hand_R", fallback = "RightHand" },
		anchorsByStep = {
			[2] = { name = "FX_Hand_L", fallback = "LeftHand" },
		},
		markers = {
			punch_windup_start = { key = "Punch_Windup", action = "start" },
			punch_windup_end = { key = "Punch_Windup", action = "stop" },
			Punch_Land = { key = "Punch_Land", isHitMarker = true },
		},
	},
	hitSounds = { "rbxassetid://9117969584" },
	castSounds = { "rbxassetid://5835032207" },
	hitConeAngle = 65,
	hitConeRange = 6,
	sfx = {
		impact = { "Punch_Hit_SFX" },
	},
}

return spec
