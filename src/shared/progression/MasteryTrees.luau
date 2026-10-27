--!strict
-- The mastery trees, as data (docs/planning/progression-launch-content.md, a first draft expected to
-- change).
--
-- Every tree has the same frame, so positions and lineage are derived rather than authored:
--   trunk  -- the root form (rank 0) and two nodes (ranks 1, 2) everyone in the track passes through
--   a, b   -- two branches of ranks 1-4; rank 1 hangs off the root
--   join   -- needs rank JOIN_RANK in both branches
--   end    -- element trees only: needs the join and the element attuned
--
-- A form node names the basic attack profiles that implement it (`shapes`); a node without them is
-- designed but not built yet. Passive effects are not applied yet, and attribute requirements are
-- shown but not enforced until the attribute point budget exists (docs/tasks/mastery-model-v2.md).
--
-- Node ids are unique across all trees. They are not saved -- selections save profile ids -- so they
-- can be renamed freely.

local MasteryTrees = {}

export type NodeKind = "form" | "infusion" | "passive" | "select" | "attuned"
export type AttributeTier = "Low" | "Mid" | "High"

export type NodeDef = {
	id: string,
	displayName: string,
	kind: NodeKind,
	branch: string,
	rank: number?,
	description: string,
	-- Form nodes: the weapon contexts it fits, and the profiles that implement it.
	contexts: { string }?,
	shapes: { string }?,
	-- Attribute name -> AttributeTier ("Low" / "Mid" / "High"). Shown on the node; not enforced yet.
	-- Plain strings in the type, since inline table literals do not narrow to the tier union.
	attributes: { [string]: string }?,
}

export type TreeDef = {
	track: string,
	-- Display names of branches "a" and "b".
	branches: { a: string, b: string },
	nodes: { NodeDef },
}

local ALL_MAGIC = { "unarmed", "wand", "staff" }
local ALL_BLADE = { "sword", "dagger", "axe" }
local ALL_BLUNT = { "unarmed", "mace" }
local BOW = { "bow" }

local TREES: { TreeDef } = {
	{
		track = "Magic",
		branches = { a = "Focus", b = "Area" },
		nodes = {
			{ id = "magic.mana_ball", displayName = "Mana Ball", kind = "form", branch = "trunk", rank = 0, contexts = ALL_MAGIC, shapes = { "wand_light_1h" }, attributes = { Intelligence = "Low" }, description = "A slow orb, three to a combo." },
			{ id = "magic.arcane_focus", displayName = "Arcane Focus", kind = "passive", branch = "trunk", rank = 1, description = "Increased magic damage." },
			{ id = "magic.mana_flow", displayName = "Mana Flow", kind = "passive", branch = "trunk", rank = 2, description = "Forms cost less mana." },
			{ id = "magic.mana_bolt", displayName = "Mana Bolt", kind = "form", branch = "a", rank = 1, contexts = ALL_MAGIC, attributes = { Intelligence = "Low" }, description = "A fast, narrow bolt: fewer, harder hits." },
			{ id = "magic.concentration", displayName = "Concentration", kind = "passive", branch = "a", rank = 2, description = "Crit chance with magic projectiles." },
			{ id = "magic.piercing_bolt", displayName = "Piercing Bolt", kind = "form", branch = "a", rank = 3, contexts = ALL_MAGIC, attributes = { Intelligence = "Mid" }, description = "Passes through targets." },
			{ id = "magic.overcharge", displayName = "Overcharge", kind = "select", branch = "a", rank = 4, description = "The last step of a magic combo hits much harder and costs more mana." },
			{ id = "magic.mana_burst", displayName = "Mana Burst", kind = "form", branch = "b", rank = 1, contexts = ALL_MAGIC, attributes = { Intelligence = "Low" }, description = "A short-range blast in front of the caster." },
			{ id = "magic.resonance", displayName = "Resonance", kind = "passive", branch = "b", rank = 2, description = "Increased area of effect." },
			{ id = "magic.scatter", displayName = "Scatter", kind = "form", branch = "b", rank = 3, contexts = { "wand", "staff" }, attributes = { Intelligence = "Mid" }, description = "The orb splits into three." },
			{ id = "magic.volatile_mana", displayName = "Volatile Mana", kind = "select", branch = "b", rank = 4, description = "Magic area hits leave a brief damaging field." },
			{ id = "magic.mana_comet", displayName = "Mana Comet", kind = "form", branch = "join", contexts = ALL_MAGIC, attributes = { Intelligence = "High" }, description = "A heavy bolt that bursts in a small area on impact." },
		},
	},
	{
		track = "Blade",
		branches = { a = "Weight", b = "Edge" },
		nodes = {
			{ id = "blade.strike", displayName = "Strike", kind = "form", branch = "trunk", rank = 0, contexts = ALL_BLADE, shapes = { "sword_light_1h", "dagger_light_1h" }, description = "The basic blade combo, animated per weapon." },
			{ id = "blade.honed_edge", displayName = "Honed Edge", kind = "passive", branch = "trunk", rank = 1, description = "Increased physical damage with blades." },
			{ id = "blade.footwork", displayName = "Footwork", kind = "passive", branch = "trunk", rank = 2, description = "Move faster during a combo." },
			{ id = "blade.wide_slash", displayName = "Wide Slash", kind = "form", branch = "a", rank = 1, contexts = { "sword", "greatsword" }, attributes = { Strength = "Low" }, description = "Broad arcs that hit several enemies." },
			{ id = "blade.heft", displayName = "Heft", kind = "passive", branch = "a", rank = 2, description = "More stagger and knockback with blades." },
			{ id = "blade.cleave", displayName = "Cleave", kind = "form", branch = "a", rank = 3, contexts = { "greatsword" }, attributes = { Strength = "Mid" }, description = "Two slow, heavy steps; the second hits a small area." },
			{ id = "blade.momentum", displayName = "Momentum", kind = "select", branch = "a", rank = 4, description = "Each step of a combo deals more than the last." },
			{ id = "blade.flurry", displayName = "Flurry", kind = "form", branch = "b", rank = 1, contexts = { "sword", "dagger" }, attributes = { Dexterity = "Low" }, description = "Five quick, light steps." },
			{ id = "blade.quick_hands", displayName = "Quick Hands", kind = "passive", branch = "b", rank = 2, description = "Increased attack speed with blades." },
			{ id = "blade.twin_fangs", displayName = "Twin Fangs", kind = "form", branch = "b", rank = 3, contexts = { "dagger" }, attributes = { Dexterity = "Mid" }, description = "An alternating-hand combo for dual daggers." },
			{ id = "blade.bloodletting", displayName = "Bloodletting", kind = "select", branch = "b", rank = 4, description = "Blade hits can cause bleeding." },
			{ id = "blade.dancing_steel", displayName = "Dancing Steel", kind = "form", branch = "join", contexts = ALL_BLADE, attributes = { Strength = "Mid", Dexterity = "Mid" }, description = "Quick steps into a heavy finisher that knocks back." },
		},
	},
	{
		track = "Blunt",
		branches = { a = "Brawler", b = "Crusher" },
		nodes = {
			{ id = "blunt.punches", displayName = "Punches", kind = "form", branch = "trunk", rank = 0, contexts = ALL_BLUNT, shapes = { "unarmed_basic" }, description = "Jab, cross, heavy; a mace bashes instead." },
			{ id = "blunt.concussive", displayName = "Concussive", kind = "passive", branch = "trunk", rank = 1, description = "More stagger with blunt hits." },
			{ id = "blunt.solid_stance", displayName = "Solid Stance", kind = "passive", branch = "trunk", rank = 2, description = "Knocked back less." },
			{ id = "blunt.rapid_jabs", displayName = "Rapid Jabs", kind = "form", branch = "a", rank = 1, contexts = { "unarmed" }, shapes = { "unarmed_rapid_jabs" }, attributes = { Dexterity = "Low" }, description = "Five quick jabs." },
			{ id = "blunt.combo_flow", displayName = "Combo Flow", kind = "passive", branch = "a", rank = 2, description = "Increased attack speed unarmed." },
			{ id = "blunt.iron_rush", displayName = "Iron Rush", kind = "form", branch = "a", rank = 3, contexts = { "unarmed" }, attributes = { Dexterity = "Mid" }, description = "A five-hit rush ending in an uppercut that knocks back." },
			{ id = "blunt.second_wind", displayName = "Second Wind", kind = "select", branch = "a", rank = 4, description = "Landing a full combo restores stamina." },
			{ id = "blunt.overhead_smash", displayName = "Overhead Smash", kind = "form", branch = "b", rank = 1, contexts = { "mace", "hammer" }, attributes = { Strength = "Low" }, description = "Slow, heavy downward blows." },
			{ id = "blunt.armor_break", displayName = "Armor Break", kind = "passive", branch = "b", rank = 2, description = "Blunt hits briefly lower the target's armor." },
			{ id = "blunt.ground_slam", displayName = "Ground Slam", kind = "form", branch = "b", rank = 3, contexts = { "hammer" }, attributes = { Strength = "Mid" }, description = "The finisher strikes a ring around the impact." },
			{ id = "blunt.daze", displayName = "Daze", kind = "select", branch = "b", rank = 4, description = "Heavy hits can stun briefly." },
			{ id = "blunt.earthshaker", displayName = "Earthshaker", kind = "form", branch = "join", contexts = ALL_BLUNT, attributes = { Strength = "Mid", Defense = "Low" }, description = "A stomp that staggers nearby enemies, then two heavy strikes." },
		},
	},
	{
		track = "Ranged",
		branches = { a = "Precision", b = "Volley" },
		nodes = {
			{ id = "ranged.shot", displayName = "Shot", kind = "form", branch = "trunk", rank = 0, contexts = BOW, attributes = { Dexterity = "Low" }, description = "A plain arrow per step." },
			{ id = "ranged.steady_aim", displayName = "Steady Aim", kind = "passive", branch = "trunk", rank = 1, description = "Faster, straighter arrows." },
			{ id = "ranged.light_quiver", displayName = "Light Quiver", kind = "passive", branch = "trunk", rank = 2, description = "Forms cost less stamina." },
			{ id = "ranged.aimed_shot", displayName = "Aimed Shot", kind = "form", branch = "a", rank = 1, contexts = BOW, attributes = { Dexterity = "Low" }, description = "Hold to draw for more damage." },
			{ id = "ranged.keen_eye", displayName = "Keen Eye", kind = "passive", branch = "a", rank = 2, description = "Crit chance with bows." },
			{ id = "ranged.piercing_arrow", displayName = "Piercing Arrow", kind = "form", branch = "a", rank = 3, contexts = BOW, attributes = { Dexterity = "Mid" }, description = "Passes through targets." },
			{ id = "ranged.weak_point", displayName = "Weak Point", kind = "select", branch = "a", rank = 4, description = "Crits against distant targets deal more." },
			{ id = "ranged.split_shot", displayName = "Split Shot", kind = "form", branch = "b", rank = 1, contexts = BOW, attributes = { Dexterity = "Low" }, description = "Three arrows in a spread." },
			{ id = "ranged.quick_draw", displayName = "Quick Draw", kind = "passive", branch = "b", rank = 2, description = "Increased attack speed with bows." },
			{ id = "ranged.arrow_rain", displayName = "Arrow Rain", kind = "form", branch = "b", rank = 3, contexts = BOW, attributes = { Dexterity = "Mid" }, description = "A lobbed volley onto the aimed point." },
			{ id = "ranged.pin_down", displayName = "Pin Down", kind = "select", branch = "b", rank = 4, description = "Volley hits slow enemies." },
			{ id = "ranged.barrage", displayName = "Barrage", kind = "form", branch = "join", contexts = BOW, attributes = { Dexterity = "High", Perception = "Low" }, description = "A rapid stream of arrows." },
		},
	},
	{
		track = "Fire",
		branches = { a = "Reach", b = "Spread" },
		nodes = {
			{ id = "fire.fire_1", displayName = "Fire I", kind = "infusion", branch = "trunk", rank = 0, description = "Part of the damage becomes fire." },
			{ id = "fire.heat", displayName = "Heat", kind = "passive", branch = "trunk", rank = 1, description = "Increased fire damage." },
			{ id = "fire.fire_ward", displayName = "Fire Ward", kind = "passive", branch = "trunk", rank = 2, description = "Fire resistance, capped low." },
			{ id = "fire.fire_2", displayName = "Fire II", kind = "infusion", branch = "a", rank = 1, description = "More becomes fire; flames extend slashes and bolts." },
			{ id = "fire.searing", displayName = "Searing", kind = "passive", branch = "a", rank = 2, description = "Fire penetration." },
			{ id = "fire.flame_reach", displayName = "Flame Reach", kind = "passive", branch = "a", rank = 3, description = "Fire forms reach further as Fire grows." },
			{ id = "fire.blaze", displayName = "Blaze", kind = "select", branch = "a", rank = 4, description = "Fire crits always ignite." },
			{ id = "fire.ignite", displayName = "Ignite", kind = "passive", branch = "b", rank = 1, description = "Fire hits can burn." },
			{ id = "fire.lingering_burn", displayName = "Lingering Burn", kind = "passive", branch = "b", rank = 2, description = "Burns last longer." },
			{ id = "fire.cinders", displayName = "Cinders", kind = "passive", branch = "b", rank = 3, description = "Burning enemies splash fire when they die." },
			{ id = "fire.wildfire", displayName = "Wildfire", kind = "select", branch = "b", rank = 4, description = "Burns spread to a nearby enemy on a kill." },
			{ id = "fire.fire_3", displayName = "Fire III", kind = "infusion", branch = "join", description = "All of it becomes fire; opens Fireball and Fire Crescent." },
			{ id = "fire.kindled_soul", displayName = "Kindled Soul", kind = "attuned", branch = "end", description = "Burns stack once more, and more fire damage." },
		},
	},
	{
		track = "Frost",
		branches = { a = "Bite", b = "Grip" },
		nodes = {
			{ id = "frost.frost_1", displayName = "Frost I", kind = "infusion", branch = "trunk", rank = 0, description = "Part of the damage becomes frost." },
			{ id = "frost.cold", displayName = "Cold", kind = "passive", branch = "trunk", rank = 1, description = "Increased frost damage." },
			{ id = "frost.frost_ward", displayName = "Frost Ward", kind = "passive", branch = "trunk", rank = 2, description = "Frost resistance, capped low." },
			{ id = "frost.frost_2", displayName = "Frost II", kind = "infusion", branch = "a", rank = 1, description = "More becomes frost; hits splinter into shards." },
			{ id = "frost.frostbite", displayName = "Frostbite", kind = "passive", branch = "a", rank = 2, description = "Frost penetration." },
			{ id = "frost.brittle", displayName = "Brittle", kind = "passive", branch = "a", rank = 3, description = "Frost crits deal more against chilled enemies." },
			{ id = "frost.shatter", displayName = "Shatter", kind = "select", branch = "a", rank = 4, description = "Killing a frozen enemy bursts it into ice." },
			{ id = "frost.chill", displayName = "Chill", kind = "passive", branch = "b", rank = 1, description = "Frost hits slow." },
			{ id = "frost.deep_chill", displayName = "Deep Chill", kind = "passive", branch = "b", rank = 2, description = "Chill is stronger and lasts longer." },
			{ id = "frost.freeze", displayName = "Freeze", kind = "passive", branch = "b", rank = 3, description = "Fully chilled enemies freeze briefly." },
			{ id = "frost.permafrost", displayName = "Permafrost", kind = "select", branch = "b", rank = 4, description = "Frost area hits leave chilling ground." },
			{ id = "frost.frost_3", displayName = "Frost III", kind = "infusion", branch = "join", description = "All of it becomes frost; opens Ice Lance and Frost Nova." },
			{ id = "frost.heart_of_winter", displayName = "Heart of Winter", kind = "attuned", branch = "end", description = "Freezes last longer, and more frost damage." },
		},
	},
}

local byTrack: { [string]: TreeDef } = {}
local nodeById: { [string]: { tree: TreeDef, node: NodeDef } } = {}
local nodeByShape: { [string]: { tree: TreeDef, node: NodeDef } } = {}

-- Fail fast on malformed content: a tree that breaks the frame would draw or unlock wrongly.
for _, tree in ipairs(TREES) do
	assert(byTrack[tree.track] == nil, `MasteryTrees: duplicate tree for track '{tree.track}'`)
	byTrack[tree.track] = tree
	for _, node in ipairs(tree.nodes) do
		assert(nodeById[node.id] == nil, `MasteryTrees: duplicate node id '{node.id}'`)
		local branch = node.branch
		assert(
			branch == "trunk" or branch == "a" or branch == "b" or branch == "join" or branch == "end",
			`MasteryTrees: node '{node.id}' has unknown branch '{branch}'`
		)
		if branch == "trunk" then
			assert(node.rank and node.rank >= 0 and node.rank <= 2, `MasteryTrees: trunk node '{node.id}' needs rank 0-2`)
		elseif branch == "a" or branch == "b" then
			assert(node.rank and node.rank >= 1 and node.rank <= 4, `MasteryTrees: branch node '{node.id}' needs rank 1-4`)
		end
		local entry = { tree = tree, node = node }
		nodeById[node.id] = entry
		for _, shapeId in ipairs(node.shapes or {}) do
			assert(nodeByShape[shapeId] == nil, `MasteryTrees: profile '{shapeId}' implements two nodes`)
			nodeByShape[shapeId] = entry
		end
	end
end

function MasteryTrees.get(trackId: string): TreeDef?
	return byTrack[trackId]
end

function MasteryTrees.node(nodeId: string): (NodeDef?, TreeDef?)
	local entry = nodeById[nodeId]
	if not entry then
		return nil, nil
	end
	return entry.node, entry.tree
end

-- The node a basic attack profile implements, and its tree.
function MasteryTrees.nodeForShape(shapeId: string): (NodeDef?, TreeDef?)
	local entry = nodeByShape[shapeId]
	if not entry then
		return nil, nil
	end
	return entry.node, entry.tree
end

return MasteryTrees
