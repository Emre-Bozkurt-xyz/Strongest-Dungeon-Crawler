--!strict
-- Unarmed BasicAttackProfile. Reproduces Punch's original 3-step jab/cross/heavy combo exactly
-- (see src/server/SkillsFramework/Skills/Punch.luau and its SkillsData/ClientSpec) plus the
-- unarmed base damage/speed/range absorbed from the Phase A CombatConfig stepping stone
-- (see src/shared/Config/CombatConfig.luau, deleted in this phase).
--
-- This is the universal fallback: BasicAttackProfileRegistry.resolve() always returns this profile
-- when the caster has no main-hand weapon, when the weapon names no basicAttackProfile, or when it
-- names one that does not exist.

local Types = require(script.Parent.Parent.BasicAttackProfileTypes)

local profile: Types.BasicAttackProfile = {
	id = "unarmed_basic",
	weaponClasses = {},
	combo = {
		steps = 3,
		window = 0.6,
		stepDurations = { 0.45, 0.4, 0.5 },
		hitDelays = { 0.32, 0.27, 0.35 },
		stepDelays = { 0.1, 0.1, 1.5 },
	},
	steps = {
		{ hand = "main", animation = "Punch_Combo_1", damageMultiplier = 0.8, coneRange = 4.5 },
		{ hand = "main", animation = "Punch_Combo_2", damageMultiplier = 0.9, coneRange = 4.5 },
		{ hand = "main", animation = "Punch_Combo_3", damageMultiplier = 1.25, coneRange = 6 },
	},
	hitCone = { angle = 65, range = 6 },
	idleAnimation = "Punch_Idle",
	unarmedBase = {
		damage = { { type = "Physical", min = 2, max = 4 } },
		attackSpeed = 1.0,
		range = 4.5,
	},
}

return profile
