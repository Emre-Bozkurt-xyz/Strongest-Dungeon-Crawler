--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Shared.skills.SkillSpecTypes)

-- Everything about the swing -- timing, animation, damage, and cost -- comes from the shape
-- BasicAttackProfileRegistry.resolve picks from the caster's combat loadout (see D6 in
-- docs/tasks/equipment-item-architecture.md). BasicAttack:use() and SkillMetadataService both read
-- the resolved shape; `combo` here is only the initial `self.config.combo` before the first use.
-- There is deliberately no `costs` here: cost belongs to the shape.
local data: Types.ServerSkillConfig = {
	name = "BasicAttack",
	tags = { "melee", "light" },
	description = "Adaptive basic attack: uses the current weapon's basic attack profile, falling back to the unarmed profile when empty-handed.",
	-- No cooldown and no GCD: the basic attack is what a character does between skills, so any
	-- lockout here is dead time whenever their skills are also cooling down. Pacing comes from the
	-- combo itself -- the finisher's `recovery` end lag and knockback in the weapon's profile.
	cooldown = 0,
	gcd = 0,
	level = 1,
	animCategory = "melee_light",
	combo = {
		steps = 3,
		window = 0.6,
		hitDelays = { 0.32, 0.27, 0.35 },
		stepDurations = { 0.45, 0.4, 0.5 },
	},
	-- Phase C (D8): declared explicitly rather than left absent (Guardrail 6) -- "adaptive" means
	-- resolution (BasicAttackProfileRegistry) already handles weapon compatibility and falls back
	-- to unarmed_basic, so the gate must never reject a BasicAttack use (trap 3).
	requirements = {
		weapon = {
			mode = "adaptive",
		},
	},
}
return data
