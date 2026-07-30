--!strict
-- Shared type definitions for BasicAttackProfileRegistry (Phase B: adaptive BasicAttack).
--
-- A BasicAttackProfile is the shared, profile-keyed content D6 in the equipment architecture doc
-- resolves for both client prediction and server execution. Both sides call
-- BasicAttackProfileRegistry.resolve() with the same CombatLoadoutSnapshot-derived input and get
-- byte-identical data back -- no replication of a resolved spec, no per-side reimplementation.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)

local Types = {}

-- Phase C (D9/dual wield): "both" is an authored choice meaning "this step intentionally uses both
-- hands" -- it never comes from alternation, only from a profile step explicitly naming it.
export type BasicAttackHand = "main" | "secondary" | "both"

-- How a combo step delivers its damage.
--
-- "cone"       -- sweep the profile's hit cone in front of the caster and damage everything in it.
-- "projectile" -- fire the *equipped weapon's* projectile (WeaponConfig.projectile) and damage
--                 whatever it hits. The step says a projectile is fired; the weapon says which one.
--                 That split is why one wand profile can serve a plain, flame and frost wand.
--
-- Omitting `delivery` means "cone" -- every profile authored before projectiles existed keeps
-- working untouched.
export type BasicAttackDelivery = "cone" | "projectile"

export type BasicAttackComboSpec = {
	steps: number,
	window: number,
	stepDurations: { number }?,
	hitDelays: { number }?,
	stepDelays: { number }?,
	recovery: number?,
}

export type BasicAttackStepSpec = {
	-- Phase C: omitting `hand` means "let HandResolver decide" -- it alternates between both hands
	-- when the current loadout is dual-wielding one-handed weapons, and otherwise resolves to
	-- whichever hand actually holds a weapon (D9). An authored hand always wins over that
	-- resolution (Guardrail 6).
	hand: BasicAttackHand?,
	animation: string,
	damageMultiplier: number,
	-- nil means "cone". See BasicAttackDelivery above.
	delivery: BasicAttackDelivery?,
	-- Animation marker that releases this step's projectile, letting the bolt leave the weapon on
	-- the frame the animation looks right rather than at an authored `hitDelays` guess. Only read on
	-- projectile-delivery steps.
	--
	-- The server stays authoritative: it arms a release when the step fires and holds it for a
	-- bounded window, so a client that never reports the marker -- animation missing it, or stalling
	-- deliberately -- still gets the projectile at the end of that window.
	releaseMarker: string?,
	-- Optional per-step hit cone override. Falls back to the profile's top-level `hitCone` when
	-- absent (unarmed_basic varies range per step to match Punch's original jab/cross/heavy feel).
	-- Read for cone steps, and by projectile steps that degrade to a cone because the equipped
	-- weapon declares no projectile.
	coneAngle: number?,
	coneRange: number?,
}

export type BasicAttackHitCone = {
	angle: number,
	range: number,
}

-- Unarmed base damage/speed/range, absorbed from the Phase A CombatConfig stepping stone into the
-- unarmed_basic profile. Only unarmed_basic populates this; BaseSkill:resolveWeaponDamage reads it
-- as the empty-handed fallback.
export type BasicAttackUnarmedBase = {
	damage: { ItemTypes.WeaponDamageRange },
	attackSpeed: number,
	range: number,
}

export type BasicAttackProfile = {
	id: string,
	-- Weapon classes (WeaponConfig.class values, e.g. "sword") that resolve to this profile when
	-- the equipped weapon does not name a basicAttackProfile explicitly, or names an unknown one.
	-- Empty for unarmed_basic: it is only ever reached via the no-weapon / unknown-id fallback path.
	weaponClasses: { ItemTypes.WeaponClass },
	combo: BasicAttackComboSpec,
	steps: { BasicAttackStepSpec },
	-- Required even on all-projectile profiles: it is the geometry the projectile-step fallback
	-- uses when the equipped weapon of that class declares no projectile.
	hitCone: BasicAttackHitCone,
	-- Looping animation held between combo steps, while the chain window is still open, so a weapon
	-- settles into its own stance instead of snapping back to the default idle mid-combo. The
	-- adaptive equivalent of a static spec's `anim.comboIdle`.
	idleAnimation: string?,
	unarmedBase: BasicAttackUnarmedBase?,
}

-- Runtime constants for the unions above, so profile authoring gets autocomplete and typo
-- checking the same way ItemEnums provides it for item authoring.
Types.Hand = {
	Main = "main" :: BasicAttackHand,
	Secondary = "secondary" :: BasicAttackHand,
	Both = "both" :: BasicAttackHand,
}

Types.Delivery = {
	Cone = "cone" :: BasicAttackDelivery,
	Projectile = "projectile" :: BasicAttackDelivery,
}

return Types
