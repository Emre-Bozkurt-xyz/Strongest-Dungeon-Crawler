--!strict
-- Character Spec Types - Visual configuration for player/NPC characters

-- Animation field can be a single asset ID or array of IDs (randomly sampled)
export type AnimationId = string | { string }

export type AnimationSet = {
	-- Combat hit reactions
	hit_light: AnimationId?, -- Light hit reaction (stagger)
	hit_heavy: AnimationId?, -- Heavy hit reaction (knockback)
	stagger: AnimationId?, -- Stagger loop animation

	-- Death/revival
	death: AnimationId?,
	revive: AnimationId?,

	-- Movement (optional overrides)
	idle: AnimationId?,
	walk: AnimationId?,
	run: AnimationId?,
	jump: AnimationId?,
	fall: AnimationId?,

	-- NPC attack animations (structured differently)
	attack: {
		default: { string }?,
		bySkill: { [string]: { string } }?,
		byCategory: { [string]: { string } }?,
	}?,
}

export type StaggerRules = {
	threshold: number, -- Damage required to trigger stagger
	duration: number, -- How long stagger lasts (seconds)
	cooldown: number, -- Minimum time between staggers (seconds)
	maxStackDamage: number?, -- If damage exceeds this, stagger is guaranteed
	canInterruptSkills: boolean, -- Whether stagger cancels active skills
}

export type CharacterSpec = {
	id: string, -- Unique identifier (e.g., "PlayerCharacter", "Goblin")
	displayName: string, -- Human-readable name

	-- Visual assets
	model: string?, -- Model path (e.g., "ReplicatedStorage/Assets/Models/Goblin")
	animations: AnimationSet, -- Animation IDs

	-- Combat properties
	stagger: StaggerRules, -- Stagger behavior rules

	-- Audio (optional)
	sounds: {
		hit: { string }?, -- Hit reaction sounds
		death: { string }?, -- Death sounds
	}?,

	-- Metadata
	tags: { string }?, -- e.g., {"humanoid", "boss", "flying"}
}

return {}
