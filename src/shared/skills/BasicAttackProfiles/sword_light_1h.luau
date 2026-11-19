--!strict
-- One-handed sword BasicAttackProfile. Values match the worked example in the "Basic Attack
-- Profiles" section of docs/tasks/equipment-item-architecture.md. Selected via
-- IronSword's equipment.weapon.basicAttackProfile = "sword_light_1h".

local Types = require(script.Parent.Parent.BasicAttackProfileTypes)

local profile: Types.BasicAttackProfile = {
	id = "sword_light_1h",
	displayName = "Slash",
	weaponClasses = { "sword" },
	cost = { resource = "Stamina", steps = { 10, 12, 15 } },
	combo = {
		steps = 3,
		window = 0.55,
		stepDurations = { 0.42, 0.4, 0.55 },
		hitDelays = { 0.22, 0.2, 0.3 },
		recovery = 0.35,
	},
	-- Phase C (D9): `hand` intentionally omitted on every step. sword_light_1h has no special
	-- dual-wield behavior of its own, so HandResolver decides per swing -- alternating main/
	-- secondary when both hands hold a valid one-handed weapon, otherwise using whichever hand
	-- actually holds the sword. See "Dual Wield Resolution" in
	-- docs/tasks/equipment-item-architecture.md.
	steps = {
		{ animation = "sword_light_1h/slash_1", damageMultiplier = 1.0 },
		{ animation = "sword_light_1h/slash_2", damageMultiplier = 1.0 },
		{
			animation = "sword_light_1h/heavy_3",
			damageMultiplier = 1.35,
			knockback = { distance = 6, duration = 0.25 },
		},
	},
	hitCone = { angle = 65, range = 6 },
	idleAnimation = "sword_light_1h/idle",
	animations = {
		slash_1 = "rbxassetid://129125203503425",
		slash_2 = "rbxassetid://136656347876691",
		heavy_3 = "rbxassetid://89593224638983",
		idle = "rbxassetid://133308871975281",
	},
}

return profile
