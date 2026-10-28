--!strict
-- The shape of a passive effect kind (NodeEffects): the module that implements one `kind` of effect.
-- A kind implements only the moments it acts in; PassiveService calls each with every effect of
-- that kind an entity has in force, so a kind that sums its effects ("increased" damage adds up) does
-- so in one place.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local NodeEffects = require(ReplicatedStorage.Shared.progression.NodeEffects)
local CombatService = require(ServerScriptService.Server.Services.CombatService)
local Filters = require(script.Parent.Filters)

-- One effect in force on one entity.
export type Active = {
	nodeId: string,
	effect: NodeEffects.Effect,
	-- Multiplier on the effect's growing magnitudes: branch growth and element attunement.
	scale: number,
	-- Unique per entity and effect, for anything the kind registers elsewhere (stat modifiers).
	sourceId: string,
}

-- An NPC that died, and who killed it.
export type KillFacts = {
	killerId: string,
	targetId: string,
	model: Model,
	position: Vector3,
}

export type Kind = {
	kind: string,
	-- Applied ahead of time from what is held (a stat while holding a blade). Called on every
	-- recompute with all of the entity's effects of this kind, possibly none, and must replace
	-- whatever it applied the previous time.
	apply: ((entityId: string, actives: { Active }, loadout: Filters.Loadout) -> ())?,
	-- An attack about to land, for the attacker's effects and for the target's. Must not yield.
	outgoing: ((ctx: CombatService.AttackHookContext, facts: Filters.HitFacts, actives: { Active }) -> ())?,
	incoming: ((ctx: CombatService.AttackHookContext, facts: Filters.HitFacts, actives: { Active }) -> ())?,
	-- An attack the entity made, after it landed (`facts` has the after-hit fields).
	afterHit: ((facts: Filters.HitFacts, actives: { Active }) -> ())?,
	-- An NPC the entity killed.
	onKill: ((kill: KillFacts, actives: { Active }) -> ())?,
	-- A use of a skill (a cast, or one combo step) the entity paid for.
	onUse: ((entityId: string, skillName: string, actives: { Active }, loadout: Filters.Loadout) -> ())?,
	-- The entity is gone; drop anything kept for it.
	clear: ((entityId: string) -> ())?,
}

return {}
