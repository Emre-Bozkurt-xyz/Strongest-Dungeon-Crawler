--!strict
-- Unarmed BasicAttackProfile. Punch's 3-step jab/cross/heavy combo
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
	displayName = "Punches",
	weaponClasses = {},
	cost = { resource = "Stamina", steps = { 10, 12, 15 } },
	combo = {
		steps = 3,
		window = 0.6,
		stepDurations = { 0.45, 0.4, 0.5 },
		hitDelays = { 0.32, 0.27, 0.35 },
		recovery = 0.3,
	},
	steps = {
		{ hand = "main", animation = "unarmed_basic/punch_1", damageMultiplier = 0.8, coneRange = 4.5 },
		{ hand = "main", animation = "unarmed_basic/punch_2", damageMultiplier = 0.9, coneRange = 4.5 },
		{
			hand = "main",
			animation = "unarmed_basic/punch_3",
			damageMultiplier = 1.25,
			coneRange = 6,
			knockback = { distance = 6, duration = 0.25 },
		},
	},
	hitCone = { angle = 65, range = 6 },
	idleAnimation = "unarmed_basic/idle",
	animations = {
		punch_1 = "rbxassetid://122752973149294",
		punch_2 = "rbxassetid://133788075368604",
		-- The opening jab again until the heavy has a clip of its own.
		punch_3 = "rbxassetid://122752973149294",
		idle = "rbxassetid://77028377379164",
	},
	unarmedBase = {
		damage = { { type = "Physical", min = 2, max = 4 } },
		attackSpeed = 1.0,
		range = 4.5,
	},
}

return profile
