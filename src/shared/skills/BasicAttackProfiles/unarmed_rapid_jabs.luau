--!strict
-- Unarmed alternative shape: a quick two-jab rhythm in place of Punches' jab/cross/heavy chain.
-- Trades the finisher (and its knockback) for speed and a lower cost, so it keeps pressure on a
-- target rather than opening space.
--
-- The first alternative shape, and the one that proves selection end to end: it reuses the punch
-- animations (played faster to fit its shorter steps) so it needs no new assets.

local Types = require(script.Parent.Parent.BasicAttackProfileTypes)

local profile: Types.BasicAttackProfile = {
	id = "unarmed_rapid_jabs",
	displayName = "Rapid Jabs",
	-- Not a default for anything: selectable for empty hands only.
	weaponClasses = {},
	-- Unlocked in the mastery trees (Blunt, Brawler rank 1: shared/progression/MasteryTrees).
	shapeFor = { Types.UNARMED_CLASS_KEY },
	cost = { resource = "Stamina", steps = { 6, 6 } },
	combo = {
		steps = 2,
		window = 0.45,
		stepDurations = { 0.3, 0.28 },
		hitDelays = { 0.2, 0.17 },
		recovery = 0.15,
	},
	steps = {
		{ hand = "main", animation = "Punch_Combo_1", damageMultiplier = 0.6, coneRange = 4.5 },
		{ hand = "main", animation = "Punch_Combo_2", damageMultiplier = 0.65, coneRange = 4.5 },
	},
	hitCone = { angle = 65, range = 4.5 },
	idleAnimation = "Punch_Idle",
}

return profile
