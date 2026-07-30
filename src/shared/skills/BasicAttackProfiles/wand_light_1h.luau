--!strict
-- One-handed wand BasicAttackProfile: the first projectile-delivery basic attack.
-- Selected via CrookedWand's equipment.weapon.basicAttackProfile = "wand_light_1h".
--
-- This profile deliberately says nothing about *which* projectile is fired -- only that each step
-- fires one. The weapon supplies the template, speed, lifetime and muzzle attachment
-- (WeaponConfig.projectile). That split is what lets this one profile serve a plain wand, a flame
-- wand and a frost wand: each declares its own damage type and its own bolt, and neither needs a
-- profile of its own. Authoring a per-element profile here would recreate the "a skill per weapon
-- type" problem Guardrail 8 exists to prevent, one level further down.
--
-- Two steps rather than three: a caster's basic attack is a rhythm of repeated casts, not a melee
-- chain building to a heavy finisher.

local Types = require(script.Parent.Parent.BasicAttackProfileTypes)

local profile: Types.BasicAttackProfile = {
	id = "wand_light_1h",
	weaponClasses = { "wand" },
	combo = {
		steps = 2,
		window = 0.65,
		stepDurations = { 0.5, 0.5 },
		-- The bolt leaves the wand partway through the cast animation, not on frame one.
		hitDelays = { 0.25, 0.25 },
	},
	-- `hand` omitted so HandResolver picks the hand holding the wand, alternating when dual-wielding
	-- (D9). Each hand fires from its own muzzle attachment.
	-- `releaseMarker` names a marker placed in the cast animations themselves, so the bolt leaves on
	-- the frame the cast reads as finished rather than at the `hitDelays` estimate above. Remove it
	-- from a step and that step falls back to the hit delay.
	steps = {
		{
			animation = "Wand_Cast_1",
			damageMultiplier = 1.0,
			delivery = "projectile",
			releaseMarker = "Release",
		},
		{
			animation = "Wand_Cast_2",
			damageMultiplier = 1.15,
			delivery = "projectile",
			releaseMarker = "Release",
		},
	},
	-- Unused while a real wand is equipped; it is the fallback geometry for a weapon that resolves
	-- here by class but declares no projectile. Kept short so a caster flailing a wand cannot
	-- out-range a sword.
	hitCone = { angle = 50, range = 4.5 },
	idleAnimation = "Wand_Idle",
}

return profile
