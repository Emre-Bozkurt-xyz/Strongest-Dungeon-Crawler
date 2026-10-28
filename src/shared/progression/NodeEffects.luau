--!strict
-- What passive nodes do: the effects of every passive, selectable passive and attunement-only node
-- in the mastery trees (MasteryTrees), as data (docs/tasks/passives.md). Forms and infusions are not
-- here; they change the basic attack itself (BasicAttackForm).
--
-- A node's effects are a list of `{ kind = ..., when = ... }` records. The kind names what the effect
-- does and which of its fields matter; the server implements each kind once
-- (server/Progression/Passives/Kinds), so a new node is usually only data. Something no kind covers
-- is a new kind there -- including one-off behaviours, which are kinds like any other.
--
-- Magnitudes grow inside a node: by up to `GROWTH` as its branch's XP runs from the node's threshold
-- to Mastered, and by `ATTUNED_ELEMENT` when an element tree is attuned. Chances, durations given in
-- seconds and thresholds do not grow; each kind says which of its fields do.
--
-- All numbers are placeholders, to tune with combat.

local MasteryTrees = require(script.Parent.MasteryTrees)
local MasteryTracks = require(script.Parent.MasteryTracks)
local MasteryXP = require(script.Parent.MasteryXP)

-- When an effect applies. Every field given must hold; an empty or missing filter always holds.
export type Filter = {
	-- Damage packets of these types (outgoing and incoming kinds), or a hit that dealt one of them
	-- (after-hit kinds).
	damageTypes: { string }?,
	-- The weapon context held: a weapon class key, or "unarmed".
	contexts: { string }?,
	-- The mastery track of the attack: the basic attack's form's track, or a skill's `mastery` tag.
	tracks: { string }?,
	skills: { string }?,
	-- "melee", "projectile" or "area" (AttackMetadata.delivery).
	delivery: { string }?,
	-- A combo step, or "final" for the last step of the form in use.
	comboStep: (string | number)?,
	-- After-hit: the hit crit (of `damageTypes`, when given).
	crit: boolean?,
	-- The target has this status, or at least this many stacks of it.
	targetHas: string?,
	targetStacks: { status: string, atLeast: number }?,
	-- The target is at least this far away (studs).
	minDistance: number?,
	-- The basic attack carries this element's infusion.
	infusion: string?,
}

export type Effect = {
	kind: string,
	when: Filter?,
	[string]: any,
}

local NodeEffects = {}

-- A node's magnitudes reach (1 + GROWTH) times their base when its branch is Mastered.
NodeEffects.GROWTH = 0.5
-- An attuned element's tree is this much stronger (progression-direction.md, attunement).
NodeEffects.ATTUNED_ELEMENT = 1.5
-- Resistance from trees, per element, before and after attuning it: low, so gear stays the main
-- source and a veteran with every element still needs it.
NodeEffects.TREE_RESISTANCE_CAP = 15
NodeEffects.TREE_RESISTANCE_CAP_ATTUNED = 20

local BLADES = { "sword", "dagger", "axe", "greatsword" }
local BLUNT = { "unarmed", "mace", "hammer" }
local HEAVY_BLUNT = { "mace", "hammer" }
local BOW = { "bow" }

local EFFECTS: { [string]: { Effect } } = {
	-- Magic
	["magic.arcane_focus"] = {
		{ kind = "damage", increased = 0.1, when = { damageTypes = { "Magic" } } },
	},
	["magic.mana_flow"] = {
		{ kind = "cost", resource = "Mana", reduced = 0.15 },
	},
	["magic.concentration"] = {
		{ kind = "critChance", value = 5, when = { tracks = { "Magic" }, delivery = { "projectile" } } },
	},
	["magic.overcharge"] = {
		{ kind = "damage", increased = 0.6, when = { tracks = { "Magic" }, comboStep = "final" } },
		{ kind = "cost", resource = "Mana", increased = 0.5, when = { tracks = { "Magic" }, comboStep = "final" } },
	},
	["magic.resonance"] = {
		{ kind = "area", increased = 0.2 },
	},
	["magic.volatile_mana"] = {
		{ kind = "field", damageShare = 0.25, radius = 6, duration = 2, element = "Magic", when = { tracks = { "Magic" }, delivery = { "area" } } },
	},

	-- Blade
	["blade.honed_edge"] = {
		{ kind = "damage", increased = 0.12, when = { damageTypes = { "Physical" }, contexts = BLADES } },
	},
	["blade.footwork"] = {
		{ kind = "moveSpeed", increased = 0.12, afterUse = { "BasicAttack" }, window = 1.2, when = { contexts = BLADES } },
	},
	["blade.heft"] = {
		{ kind = "stagger", dealt = 0.3, when = { contexts = BLADES } },
		{ kind = "knockback", dealt = 0.3, when = { contexts = BLADES } },
	},
	["blade.momentum"] = {
		{ kind = "damage", perComboStep = 0.1, when = { contexts = { "sword", "greatsword" } } },
	},
	["blade.quick_hands"] = {
		{ kind = "stat", stat = "AttackSpeed", mode = "percent", value = 0.08, when = { contexts = BLADES } },
	},
	["blade.bloodletting"] = {
		{ kind = "onHit", status = "Bleed", chance = 0.25, fromDamage = { damagePerTick = 0.05 }, when = { contexts = BLADES, damageTypes = { "Physical" } } },
	},

	-- Blunt
	["blunt.concussive"] = {
		{ kind = "stagger", dealt = 0.4, when = { contexts = BLUNT } },
	},
	["blunt.solid_stance"] = {
		{ kind = "knockback", taken = -0.4 },
	},
	["blunt.combo_flow"] = {
		{ kind = "stat", stat = "AttackSpeed", mode = "percent", value = 0.1, when = { contexts = { "unarmed" } } },
	},
	["blunt.second_wind"] = {
		{ kind = "restore", resource = "Stamina", amount = 12, when = { contexts = { "unarmed" }, comboStep = "final" } },
	},
	["blunt.armor_break"] = {
		{ kind = "onHit", status = "Sunder", chance = 0.3, params = { armorReduction = 0.25, duration = 4 }, when = { contexts = BLUNT, damageTypes = { "Physical" } } },
	},
	["blunt.daze"] = {
		{ kind = "onHit", status = "stun", chance = 0.15, params = { duration = 0.6 }, cooldown = 3, when = { contexts = HEAVY_BLUNT, comboStep = "final" } },
	},

	-- Ranged
	["ranged.steady_aim"] = {
		{ kind = "projectileSpeed", increased = 0.2, when = { contexts = BOW } },
	},
	["ranged.light_quiver"] = {
		{ kind = "cost", resource = "Stamina", reduced = 0.15, when = { contexts = BOW } },
	},
	["ranged.keen_eye"] = {
		{ kind = "critChance", value = 5, when = { contexts = BOW } },
	},
	["ranged.weak_point"] = {
		{ kind = "critDamage", increased = 0.4, when = { contexts = BOW, minDistance = 20 } },
	},
	["ranged.quick_draw"] = {
		{ kind = "stat", stat = "AttackSpeed", mode = "percent", value = 0.08, when = { contexts = BOW } },
	},
	["ranged.pin_down"] = {
		{ kind = "onHit", status = "Slow", chance = 1, params = { amount = 0.3, duration = 1.5 }, when = { tracks = { "Ranged" } } },
	},

	-- Fire
	["fire.heat"] = {
		{ kind = "damage", increased = 0.12, when = { damageTypes = { "Fire" } } },
	},
	["fire.fire_ward"] = {
		{ kind = "resistance", element = "Fire", value = 8 },
	},
	["fire.searing"] = {
		{ kind = "stat", stat = "FirePenetration", mode = "flat", value = 10 },
	},
	["fire.flame_reach"] = {
		{ kind = "reach", increased = 0.2, when = { infusion = "Fire" } },
	},
	["fire.blaze"] = {
		{ kind = "onHit", status = "Burn", chance = 1, fromDamage = { damagePerTick = 0.12 }, when = { crit = true, damageTypes = { "Fire" } } },
	},
	["fire.ignite"] = {
		{ kind = "onHit", status = "Burn", chance = 0.25, fromDamage = { damagePerTick = 0.12 }, when = { damageTypes = { "Fire" } } },
	},
	["fire.lingering_burn"] = {
		{ kind = "statusBoost", status = "Burn", duration = 0.5 },
	},
	["fire.cinders"] = {
		{ kind = "onKill", action = "explode", element = "Fire", maxHealthShare = 0.1, radius = 8, when = { targetHas = "Burn" } },
	},
	["fire.wildfire"] = {
		{ kind = "onKill", action = "spread", status = "Burn", radius = 12, count = 1, when = { targetHas = "Burn" } },
	},
	["fire.kindled_soul"] = {
		{ kind = "statusBoost", status = "Burn", extraStacks = 1 },
		{ kind = "damage", increased = 0.1, when = { damageTypes = { "Fire" } } },
	},

	-- Frost
	["frost.cold"] = {
		{ kind = "damage", increased = 0.12, when = { damageTypes = { "Frost" } } },
	},
	["frost.frost_ward"] = {
		{ kind = "resistance", element = "Frost", value = 8 },
	},
	["frost.frostbite"] = {
		{ kind = "stat", stat = "FrostPenetration", mode = "flat", value = 10 },
	},
	["frost.brittle"] = {
		{ kind = "critDamage", increased = 0.3, when = { damageTypes = { "Frost" }, targetHas = "Chill" } },
	},
	["frost.shatter"] = {
		{ kind = "onKill", action = "explode", element = "Frost", maxHealthShare = 0.15, radius = 8, status = "Chill", when = { targetHas = "Freeze" } },
	},
	["frost.chill"] = {
		{ kind = "onHit", status = "Chill", chance = 1, params = { duration = 3 }, when = { damageTypes = { "Frost" } } },
	},
	["frost.deep_chill"] = {
		{ kind = "statusBoost", status = "Chill", duration = 0.5, potency = 0.4 },
	},
	["frost.freeze"] = {
		{ kind = "onHit", status = "Freeze", chance = 1, params = { duration = 1 }, cooldown = 4, when = { damageTypes = { "Frost" }, targetStacks = { status = "Chill", atLeast = 5 } } },
	},
	["frost.permafrost"] = {
		{ kind = "field", radius = 6, duration = 3, status = "Chill", when = { damageTypes = { "Frost" }, delivery = { "area" } } },
	},
	["frost.heart_of_winter"] = {
		{ kind = "statusBoost", status = "Freeze", duration = 0.5 },
		{ kind = "damage", increased = 0.1, when = { damageTypes = { "Frost" } } },
	},
}

-- Every passive, selectable passive and attunement-only node has effects, and only those nodes do:
-- a node the canvas offers must do something, and a typo in an id would silently do nothing.
local EFFECT_KINDS = { passive = true, select = true, attuned = true }
for nodeId, effects in pairs(EFFECTS) do
	local node = MasteryTrees.node(nodeId)
	assert(node, `NodeEffects: unknown node '{nodeId}'`)
	assert(EFFECT_KINDS[node.kind], `NodeEffects: '{nodeId}' is a {node.kind} node; only passives carry effects`)
	assert(#effects > 0, `NodeEffects: '{nodeId}' has an empty effect list`)
end
for _, track in ipairs(MasteryTracks.list()) do
	local tree = MasteryTrees.get(track.id)
	for _, node in ipairs(if tree then tree.nodes else {}) do
		assert(
			not EFFECT_KINDS[node.kind] or EFFECTS[node.id] ~= nil,
			`NodeEffects: {node.kind} node '{node.id}' has no effects`
		)
	end
end

function NodeEffects.of(nodeId: string): { Effect }?
	return EFFECTS[nodeId]
end

-- How far a node has grown inside itself: 0 when just unlocked, 1 when its branch is Mastered.
function NodeEffects.growthOf(node: MasteryTrees.NodeDef, branches: { [string]: number }): number
	local function along(branch: string, from: number): number
		local cap = MasteryXP.capOf(branch)
		if cap <= from then
			return 1
		end
		return math.clamp(((branches[branch] or 0) - from) / (cap - from), 0, 1)
	end
	local rank = node.rank or 0
	if node.branch == "trunk" then
		return along("trunk", MasteryXP.TRUNK_RANKS[rank] or 0)
	elseif node.branch == "a" or node.branch == "b" then
		return along(node.branch, MasteryXP.BRANCH_RANKS[rank] or 0)
	end
	-- Join and end nodes sit past both branches: they grow with the slower of the two.
	local from = MasteryXP.BRANCH_RANKS[MasteryXP.JOIN_RANK] or 0
	return math.min(along("a", from), along("b", from))
end

-- What a node's growing magnitudes are multiplied by now: its growth, and attunement for an element.
-- The server applies this and the canvas shows it, so they cannot disagree.
function NodeEffects.scaleOf(
	node: MasteryTrees.NodeDef,
	trackId: string,
	branches: { [string]: number },
	attuned: boolean
): number
	local scale = 1 + NodeEffects.GROWTH * NodeEffects.growthOf(node, branches)
	local track = MasteryTracks.get(trackId)
	if track and track.family == "element" and attuned then
		scale *= NodeEffects.ATTUNED_ELEMENT
	end
	return scale
end

-- Whether a node of this kind carries effects (and is therefore covered here).
function NodeEffects.carriesEffects(kind: string): boolean
	return EFFECT_KINDS[kind] == true
end

return NodeEffects
