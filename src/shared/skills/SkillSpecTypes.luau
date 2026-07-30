--!strict
-- Shared type definitions for client-facing skill specs.

local SkillRequirementTypes = require(script.Parent.SkillRequirementTypes)

local Types = {}

export type AnimKeySpec = { key: string }
export type AnimSpec = {
	start: AnimKeySpec?,
	finish: AnimKeySpec?,
	comboSteps: { AnimKeySpec }?,
	comboIdle: string?,
}

export type FXAnchorSpec = { name: string, fallback: string? }
export type FXMarkerAction = string
export type FXMarkerSpec = { key: string, action: string?, isHitMarker: boolean? }
export type FXMarkerValue = string | FXMarkerSpec
export type FXSpec = {
	anchor: FXAnchorSpec?,
	anchorsByStep: { [number]: FXAnchorSpec }?,
	markers: { [string]: FXMarkerValue }?,
	impact: { string }?,
	release: string?,
}

export type SFXSpec = {
	impact: { string }?,
	start: { string }?,
	loop: { string }?,
	finish: { string }?,
}

export type ComboSpec = {
	steps: number,
	window: number,
	stepDurations: { number }?,
}

export type CameraSpec = {
	priority: number?,
	duration: number?,
	shoulderOffset: Vector3?,
	shoulderRight: number?,
	shoulderUp: number?,
	shoulderBack: number?,
	followSmoothness: number?,
	lookSmoothness: number?,
	fov: number?,
	lockYaw: boolean?,
	lockPitch: boolean?,
	shake: any?,
}

export type DirectionalVisualSpec = {
	anim: AnimSpec?,
	fx: FXSpec?,
	sfx: SFXSpec?,
	camera: CameraSpec?,
}
export type DirectionalSpecMap = { [string]: DirectionalVisualSpec }

export type TargetingSpec = {
	maxRange: number?,
}

export type FlurrySpec = {
	count: number,
	interval: number,
	jitter: number?,
	startDelay: number?,
}

export type ChargeSpec = {
	maxCount: number,
	interval: number,
	radius: number,
	radiusJitter: number?,
	height: number?,
	heightJitter: number?,
	arcMinDeg: number?,
	arcMaxDeg: number?,
	arcSymmetric: boolean?,
	arcOscAmplitude: number?,
	arcOscSpeed: number?,
	wobble: number?,
	wobbleSpeed: number?,
	forwardOffset: number?,
	maxRadius: number?,
}

export type GuidanceSpec = {
	kind: "homing" | string,
	targetEntityId: string?,
	targetTag: string?,
	factionRelation: ("ally" | "enemy" | "neutral")?,
	maxRange: number?,
	turnRate: number?,
	reacquire: boolean?,
	maxHomingTime: number?,
	influence: number?,
	weight: number?,
	startDistance: number?,
	fullDistance: number?,
	speed: number?,
}

export type ProjectileArcSpec = {
	amplitude: number,
	amplitudeJitter: number?,
	orientationMin: number?,
	orientationMax: number?,
	orientationSymmetric: boolean?,
	orientationMode: "random" | "outward" | "inward" | string?,
	orientationJitter: number?,
	plane: "vertical" | "horizontal" | string?,
}

export type ProjectilePatternSpec = {
	spread: number?,
	amplitude: number?,
	amplitudeJitter: number?,
	frequency: number?,
	frequencyJitter: number?,
	groupSize: number?,
	verticalBias: number?,
	verticalBiasJitter: number?,
	phaseJitter: number?,
	flightTimeMin: number?,
	flightTimeMax: number?,
}

export type ProjectileImpactSpec = {
	mode: "explode" | "direct" | string,
	radius: number?,
	onEnd: boolean?,
}

export type ProjectileSpec = {
	templateKey: string,
	attachPart: string?,
	partName: string?,
	movementType: string?,
	movementParams: any?,
	launchSpeed: number?,
	gravity: number?,
	lifetime: number?,
	radius: number?,
	pierce: number?,
	speculativeImpact: boolean?,
	guidance: GuidanceSpec?,
	guidanceStack: { GuidanceSpec }?,
	extraData: { [string]: any }?,
	arc: ProjectileArcSpec?,
	pattern: ProjectilePatternSpec?,
	impact: ProjectileImpactSpec?,
}

-- One open spec type covering every skill. The fields above are composable capabilities: a skill
-- opts into projectiles by setting `projectile`, into combos by setting `combo`, and so on.
--
-- Adding a skill must not require editing this file. A skill that wants to *require* one of these
-- capabilities rather than leave it optional states that in its own spec file:
--
--   local spec: Types.SkillSpec & { projectile: Types.ProjectileSpec } = { ... }
--
-- which keeps the constraint next to the content it constrains.
export type SkillSpec = {
	class: string,
	icon: string?,
	label: string?,
	tags: { string }?,
	anim: AnimSpec?,
	fx: FXSpec?,
	sfx: SFXSpec?,
	hitSounds: { string }?,
	castSounds: { string }?,
	hitConeAngle: number?,
	hitConeRange: number?,
	combo: ComboSpec?,
	directional: DirectionalSpecMap?,
	projectile: ProjectileSpec?,
	targeting: TargetingSpec?,
	flurry: FlurrySpec?,
	charge: ChargeSpec?,
	-- Phase B (adaptive BasicAttack, see D6 in equipment-item-architecture.md): when true,
	-- BasicComboSkill resolves combo/anim from BasicAttackProfileRegistry via CombatLoadoutMirror
	-- instead of reading `anim.comboSteps` / `combo` statically off this spec. Additive: skills
	-- that leave this unset keep the static path unchanged.
	adaptiveBasicAttack: boolean?,
}

export type SkillSpecMap = { [string]: SkillSpec }

export type ProjectileServerSpec = {
	radius: number?,
	pierce: number?,
	impact: ProjectileImpactSpec?,
}

export type ComboServerSpec = {
	steps: number?,
	window: number?,
	stepDelays: { number }?,
	hitDelays: { number }?,
	stepDurations: { number }?,
}

export type HitSpec = {
	t: number,
	yaw: number?,
	coneAngle: number?,
	coneRange: number?,
	damageMult: number?,
}

export type ServerSkillConfig = {
	name: string,
	description: string?,
	tags: { string }?,
	cooldown: number?,
	gcd: number?,
	level: number?,
	cost: number?,
	costs: { number }?,
	baseResource: any?,
	baseDuration: number?,
	animCategory: string?,
	combo: ComboServerSpec?,
	hits: { HitSpec }?,
	damage: number?,
	damageMult: number?,
	distance: number?,
	invulnerabilityDuration: number?,
	projectileServer: ProjectileServerSpec?,
	-- Phase C (D8, docs/tasks/equipment-item-architecture.md): eligibility gate, authored once here
	-- and read by both SkillsManager.useSkill (authoritative) and the client preflight via
	-- replicated metadata (SkillMetadataService). Additive -- skills that omit this are ungated,
	-- matching every skill's behavior before Phase C.
	requirements: SkillRequirementTypes.SkillRequirements?,
}

return Types
