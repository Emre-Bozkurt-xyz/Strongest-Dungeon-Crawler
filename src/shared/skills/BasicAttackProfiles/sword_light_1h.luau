--!strict
-- One-handed sword BasicAttackProfile. Values match the worked example in the "Basic Attack
-- Profiles" section of docs/tasks/equipment-item-architecture.md. Selected via
-- IronSword's equipment.weapon.basicAttackProfile = "sword_light_1h".

local Types = require(script.Parent.Parent.BasicAttackProfileTypes)

local profile: Types.BasicAttackProfile = {
	id = "sword_light_1h",
	weaponClasses = { "sword" },
	combo = {
		steps = 3,
		window = 0.55,
		stepDurations = { 0.42, 0.4, 0.55 },
		hitDelays = { 0.22, 0.2, 0.3 },
	},
	-- Phase C (D9): `hand` intentionally omitted on every step. sword_light_1h has no special
	-- dual-wield behavior of its own, so HandResolver decides per swing -- alternating main/
	-- secondary when both hands hold a valid one-handed weapon, otherwise using whichever hand
	-- actually holds the sword. See "Dual Wield Resolution" in
	-- docs/tasks/equipment-item-architecture.md.
	steps = {
		{ animation = "Sword_1H_Slash_1", damageMultiplier = 1.0 },
		{ animation = "Sword_1H_Slash_2", damageMultiplier = 1.0 },
		{ animation = "Sword_1H_Heavy_3", damageMultiplier = 1.35 },
	},
	hitCone = { angle = 65, range = 6 },
	idleAnimation = "Sword_1H_Idle",
}

return profile
