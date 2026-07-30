--!strict
-- Shared type definitions for skill usage requirements (Phase C, D8 in
-- docs/tasks/equipment-item-architecture.md).
--
-- D8: two layers with one job each. This module describes LAYER 1 only -- "can this skill be
-- used at all". LAYER 2 ("how does it execute") is BasicAttackProfileRegistry's job; folding
-- profile compatibility into this schema would create a second authority on the same question,
-- which D8 explicitly rejects.

local Types = {}

export type WeaponRequirementMode =
	"adaptive" -- never gates; resolution (BasicAttackProfileRegistry) already handles compatibility (D8, trap 3)
	| "any" -- any equipped hand (main or secondary weapon) satisfying classes/tags is enough
	| "main" -- must use the main-hand weapon specifically
	| "secondary" -- must use the secondary-hand weapon specifically
	| "both" -- the skill intentionally uses both hands
	| "optional" -- weapon can enhance the skill but is never required; gates like "adaptive"

export type WeaponRequirement = {
	mode: WeaponRequirementMode,
	-- Weapon classes that satisfy this requirement (e.g. { "sword", "axe", "dagger" }). Omitted or
	-- empty means any class is acceptable as long as the relevant hand holds a weapon.
	classes: { string }?,
	-- Weapon tags that must ALL be present (e.g. { "melee" }).
	tags: { string }?,
	-- Whether being empty-handed satisfies this requirement. Only consulted for modes that check a
	-- specific hand ("any"/"main"/"secondary"/"both"); "adaptive"/"optional" never gate at all.
	allowUnarmed: boolean?,
	-- When set, the Secondary slot must hold an offhand item of this OffhandType (e.g. "shield")
	-- rather than a weapon. Independent of `mode`/`classes`/`tags` -- see
	-- SkillRequirementResolver.evaluate.
	offhandType: string?,
}

export type SkillRequirements = {
	weapon: WeaponRequirement?,
}

return Types
