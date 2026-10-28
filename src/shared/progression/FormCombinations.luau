--!strict
-- Named combinations: specific shape + infusion pairings that get their own identity -- a name, a
-- look, a mechanic -- on top of the generic rule every pairing already follows
-- (docs/planning/progression-direction.md, "Forms"; progression-launch-content.md, "Named
-- combinations at launch").
--
-- Keyed by node ids (MasteryTrees), not profile ids: a combination belongs to the form, whichever
-- weapon's profile implements it. Pairings whose shape has no profile yet are listed anyway, so the
-- canvas can advertise them; they never resolve until the shape can be selected.

local MasteryTrees = require(script.Parent.MasteryTrees)

-- How a combination changes a projectile step. Placeholder numbers, to tune with combat.
export type ProjectileOverride = {
	-- Size of the projectile, relative to the shape's own.
	scale: number?,
	-- Size of its impact effect, relative to the shape's own; an explosion reads larger than its orb.
	impactScale: number?,
	-- On impact, also hits every other enemy within this radius (studs)...
	explosionRadius: number?,
	-- ...for this share of the step's damage.
	explosionDamage: number?,
}

export type Combination = {
	id: string,
	displayName: string,
	description: string,
	-- Shape node and infusion node it pairs.
	shape: string,
	infusion: string,
	-- Added to the form's own cost, as a share of it, on top of what the infusion costs.
	surcharge: number?,
	projectile: ProjectileOverride?,
}

local COMBINATIONS: { Combination } = {
	{
		id = "fire_bolt",
		displayName = "Fire Bolt",
		description = "Its own projectile.",
		shape = "magic.piercing_bolt",
		infusion = "fire.fire_2",
	},
	{
		id = "fireball",
		displayName = "Fireball",
		description = "A heavier orb that explodes on impact.",
		shape = "magic.mana_ball",
		infusion = "fire.fire_3",
		surcharge = 0.2,
		projectile = { scale = 1.8, impactScale = 4, explosionRadius = 8, explosionDamage = 0.6 },
	},
	{
		id = "fire_crescent",
		displayName = "Fire Crescent",
		description = "A crescent leaves the swing; its reach grows with Fire.",
		shape = "blade.wide_slash",
		infusion = "fire.fire_3",
	},
	{
		id = "ice_lance",
		displayName = "Ice Lance",
		description = "Pierces and chills everything it passes.",
		shape = "magic.piercing_bolt",
		infusion = "frost.frost_2",
	},
	{
		id = "frost_nova",
		displayName = "Frost Nova",
		description = "A freezing ring around the caster.",
		shape = "magic.mana_burst",
		infusion = "frost.frost_3",
	},
	{
		id = "glacial_slam",
		displayName = "Glacial Slam",
		description = "The ring freezes the ground.",
		shape = "blunt.ground_slam",
		infusion = "frost.frost_3",
	},
	{
		id = "firestorm",
		displayName = "Firestorm",
		description = "Burning arrows rain on the area.",
		shape = "ranged.arrow_rain",
		infusion = "fire.fire_3",
	},
}

local FormCombinations = {}

local byPair: { [string]: Combination } = {}

local function pairKey(shapeNode: string, infusionNode: string): string
	return `{shapeNode}+{infusionNode}`
end

for _, combination in ipairs(COMBINATIONS) do
	local shape = MasteryTrees.node(combination.shape)
	local infusion = MasteryTrees.node(combination.infusion)
	assert(shape and shape.kind == "form", `FormCombinations: '{combination.id}' names '{combination.shape}', which is not a form node`)
	assert(
		infusion and infusion.kind == "infusion",
		`FormCombinations: '{combination.id}' names '{combination.infusion}', which is not an infusion node`
	)
	local key = pairKey(combination.shape, combination.infusion)
	assert(byPair[key] == nil, `FormCombinations: two combinations for {key}`)
	byPair[key] = combination
end

-- The combination a shape node and an infusion node make together, if they are a named pair.
function FormCombinations.find(shapeNode: string?, infusionNode: string?): Combination?
	if not shapeNode or not infusionNode then
		return nil
	end
	return byPair[pairKey(shapeNode, infusionNode)]
end

function FormCombinations.list(): { Combination }
	return COMBINATIONS
end

return FormCombinations
