--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)
local Types = require(ReplicatedStorage.Shared.skills.SkillSpecTypes)

-- Static fallback shape, used only for cost/metadata bookkeeping (SkillMetadataService reads
-- `combo.steps` to build per-step comboCosts) and as the initial `self.config.combo` before the
-- first `use()` call. The authoritative per-step timing, animation, and damage multiplier for
-- each swing comes from BasicAttackProfileRegistry.resolve, keyed off the caster's current combat
-- loadout (see D6 in docs/tasks/equipment-item-architecture.md).
-- BasicAttack:use() overwrites self.config.combo with the resolved profile's combo every call, so
-- this only needs to agree on step count (3, matching both authored profiles today) for cost
-- previews to line up; per-step animation/timing/damage differences are handled entirely by the
-- profile registry on both client and server.
local data: Types.ServerSkillConfig = {
	name = "BasicAttack",
	tags = { "melee", "light" },
	description = "Adaptive basic attack: uses the current weapon's basic attack profile, falling back to the unarmed profile when empty-handed.",
	cooldown = 2.0,
	gcd = 1.0,
	level = 1,
	animCategory = "melee_light",
	combo = {
		steps = 3,
		window = 0.6,
		stepDelays = { 0.1, 0.1, 1.5 },
		hitDelays = { 0.32, 0.27, 0.35 },
		stepDurations = { 0.45, 0.4, 0.5 },
	},
	costs = { 10, 12, 15 },
	baseResource = StatTypes.PoolStats.Stamina,
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
