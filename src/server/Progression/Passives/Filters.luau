--!strict
-- When a passive effect applies: matching an effect's `when` (NodeEffects.Filter) against what is
-- known about a hit, or, for effects applied ahead of time (a stat while holding a blade), against
-- what the character holds.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local NodeEffects = require(ReplicatedStorage.Shared.progression.NodeEffects)

local StatusEffectsService = require(ServerScriptService.Server.StatusEffects.StatusEffectsService)

type Filter = NodeEffects.Filter

-- What a character is fighting with, for effects decided ahead of time.
export type Loadout = {
	-- Weapon class key held, or "unarmed".
	context: string,
	-- The basic attack's infusion element, if any.
	infusion: string?,
	-- Attuned track ids, for kinds whose limits depend on attunement (tree resistance).
	attuned: { [string]: boolean }?,
}

-- What is known about one hit. The after-hit fields are only set once it has landed.
export type HitFacts = Loadout & {
	sourceId: string,
	targetId: string,
	skillId: string?,
	delivery: string?,
	comboStep: number?,
	-- The step is the last of the form in use.
	finalStep: boolean,
	-- The mastery track the attack belongs to.
	track: string?,
	-- Studs between attacker and target, when both have a body.
	distance: number?,
	-- After the hit: what it dealt by type, and which types crit.
	byType: { [string]: number }?,
	critTypes: { [string]: boolean }?,
}

local Filters = {}

local function contains(list: { string }?, value: string?): boolean
	return list == nil or (value ~= nil and table.find(list, value) ~= nil)
end

-- The parts of a filter that depend only on what is held.
function Filters.matchesLoadout(filter: Filter?, loadout: Loadout): boolean
	if not filter then
		return true
	end
	return contains(filter.contexts, loadout.context)
		and (filter.infusion == nil or filter.infusion == loadout.infusion)
end

-- Whether the after-hit facts show damage of one of `types` (or any damage, without `types`).
local function dealtAny(types: { string }?, byType: { [string]: number }?): boolean
	if not byType then
		return types == nil
	end
	for damageType, amount in pairs(byType) do
		if amount > 0 and contains(types, damageType) then
			return true
		end
	end
	return false
end

local function critAny(types: { string }?, critTypes: { [string]: boolean }?): boolean
	if not critTypes then
		return false
	end
	for damageType in pairs(critTypes) do
		if contains(types, damageType) then
			return true
		end
	end
	return false
end

-- A whole filter against one hit. `packetType`: the damage type of the packet being changed, for
-- effects that change packets (the filter's `damageTypes` then refers to that packet); nil for
-- effects that react to the hit as a whole (it then refers to what the hit dealt).
function Filters.matchesHit(filter: Filter?, facts: HitFacts, packetType: string?): boolean
	if not filter then
		return true
	end
	if not Filters.matchesLoadout(filter, facts) then
		return false
	end
	if not contains(filter.tracks, facts.track) or not contains(filter.skills, facts.skillId) then
		return false
	end
	if not contains(filter.delivery, facts.delivery) then
		return false
	end
	local step = filter.comboStep
	if step == "final" then
		if not facts.finalStep then
			return false
		end
	elseif type(step) == "number" and facts.comboStep ~= step then
		return false
	end
	if filter.damageTypes then
		if packetType then
			if not table.find(filter.damageTypes, packetType) then
				return false
			end
		elseif not dealtAny(filter.damageTypes, facts.byType) then
			return false
		end
	end
	if filter.crit ~= nil then
		local crit = critAny(filter.damageTypes, facts.critTypes)
		if crit ~= filter.crit then
			return false
		end
	end
	if filter.targetHas and not StatusEffectsService.has(facts.targetId, filter.targetHas) then
		return false
	end
	local stacks = filter.targetStacks
	if stacks and StatusEffectsService.getStacks(facts.targetId, stacks.status) < stacks.atLeast then
		return false
	end
	if filter.minDistance and (facts.distance == nil or facts.distance < filter.minDistance) then
		return false
	end
	return true
end

return Filters
