--!strict
-- One-handed dagger BasicAttackProfile. Selected via IronDagger's
-- equipment.weapon.basicAttackProfile = "dagger_light_1h".
--
-- Shaped against sword_light_1h as the deliberate contrast: faster steps, shorter reach, a
-- narrower arc, and no heavy finisher. The dagger's damage advantage lives in its item stats
-- (higher attackSpeed and critChance), not in this profile's multipliers.

local Types = require(script.Parent.Parent.BasicAttackProfileTypes)

local profile: Types.BasicAttackProfile = {
	id = "dagger_light_1h",
	weaponClasses = { "dagger" },
	combo = {
		steps = 3,
		window = 0.45,
		stepDurations = { 0.28, 0.26, 0.34 },
		hitDelays = { 0.14, 0.13, 0.18 },
	},
	-- `hand` omitted so HandResolver alternates when dual-wielding (D9).
	steps = {
		{ animation = "Dagger_1H_Stab_1", damageMultiplier = 0.85 },
		{ animation = "Dagger_1H_Stab_2", damageMultiplier = 0.85 },
		{ animation = "Dagger_1H_Slash_3", damageMultiplier = 1.1 },
	},
	hitCone = { angle = 45, range = 4.5 },
	idleAnimation = "Dagger_1H_Idle",
}

return profile
