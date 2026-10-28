--!strict
-- The basic attack as the player has composed it (docs/planning/progression-direction.md,
-- "Forms"): the shape for what they hold, the infusion they selected, and the named combination the
-- two make, if they are a named pair.
--
-- Resolved from the combat loadout snapshot alone, like the shape it builds on
-- (BasicAttackProfileRegistry.resolve), so both peers and every server consumer -- the swing, its
-- cost, the metadata the client predicts from, mastery credit -- arrive at the same form. The server
-- has already checked the selections before writing them into the snapshot.
--
-- The generic rule: an infusion converts its share of the form's damage to its element, and the
-- converted damage is scaled by the infusion's potency (the element's mastery and attunement).
-- Every pairing works this way; a named combination adds its own name, cost and mechanic on top.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)
local BasicAttackProfileRegistry = require(script.Parent.BasicAttackProfileRegistry)
local BasicAttackProfileTypes = require(script.Parent.BasicAttackProfileTypes)
local MasteryTrees = require(ReplicatedStorage.Shared.progression.MasteryTrees)
local FormCombinations = require(ReplicatedStorage.Shared.progression.FormCombinations)

type Profile = BasicAttackProfileTypes.BasicAttackProfile

export type ActiveInfusion = {
	-- Infusion node id.
	id: string,
	displayName: string,
	element: string,
	conversion: number,
	potency: number,
}

export type Form = {
	profile: Profile,
	displayName: string,
	-- The node the shape implements, if it is part of a tree.
	shapeNode: string?,
	infusion: ActiveInfusion?,
	combination: FormCombinations.Combination?,
	-- What each step costs: the shape's own resource (with a combination's surcharge, and the
	-- infusion's cost when it spends the same resource), and `extra` resources besides.
	cost: Cost,
}

export type Cost = {
	resource: string,
	steps: { number },
	extra: { { resource: string, steps: { number } } },
}

-- Same shape as AttackResolver.TypedDamage; restated so shared code need not reach into the server.
export type TypedDamage = {
	type: string,
	amount: number,
}

local BasicAttackForm = {}

-- Converted damage grows with the element's mastery level, and more when the element is attuned
-- ("Attuning the element multiplies its tree's stats"). Placeholders, to tune with combat.
BasicAttackForm.POTENCY_PER_LEVEL = 0.01
BasicAttackForm.ATTUNED_POTENCY = 1.5

function BasicAttackForm.potencyFor(elementLevel: number, attuned: boolean): number
	return 1 + BasicAttackForm.POTENCY_PER_LEVEL * elementLevel * (if attuned then BasicAttackForm.ATTUNED_POTENCY else 1)
end

local function infusionOf(loadout: ItemTypes.CombatLoadoutSnapshot?): ActiveInfusion?
	local selected = loadout and loadout.basicAttackInfusion
	if not selected then
		return nil
	end
	local node = MasteryTrees.node(selected.id)
	local def = node and node.infusion
	if not node or not def then
		return nil
	end
	return {
		id = node.id,
		displayName = node.displayName,
		element = def.element,
		conversion = def.conversion,
		potency = if type(selected.potency) == "number" and selected.potency > 0 then selected.potency else 1,
	}
end

function BasicAttackForm.resolve(loadout: ItemTypes.CombatLoadoutSnapshot?): Form
	local profile = BasicAttackProfileRegistry.resolve(loadout)
	local shapeNode = MasteryTrees.nodeForShape(profile.id)
	local infusion = infusionOf(loadout)
	local combination = if infusion and shapeNode then FormCombinations.find(shapeNode.id, infusion.id) else nil

	local surcharge = if combination then combination.surcharge or 0 else 0
	local steps: { number } = {}
	for i, amount in ipairs(profile.cost.steps) do
		steps[i] = math.floor(amount * (1 + surcharge) + 0.5)
	end
	local extra: { { resource: string, steps: { number } } } = {}
	local infusionNode = if infusion then MasteryTrees.node(infusion.id) else nil
	local infusionCost = infusionNode and infusionNode.infusion and infusionNode.infusion.cost
	if infusionCost and infusionCost.perStep > 0 then
		if infusionCost.resource == profile.cost.resource then
			for i in ipairs(steps) do
				steps[i] += infusionCost.perStep
			end
		else
			local perStep: { number } = {}
			for i in ipairs(steps) do
				perStep[i] = infusionCost.perStep
			end
			table.insert(extra, { resource = infusionCost.resource, steps = perStep })
		end
	end

	local displayName = if combination
		then combination.displayName
		elseif infusion then `{infusion.element} {profile.displayName}`
		else profile.displayName

	return {
		profile = profile,
		displayName = displayName,
		shapeNode = if shapeNode then shapeNode.id else nil,
		infusion = infusion,
		combination = combination,
		cost = { resource = profile.cost.resource, steps = steps, extra = extra },
	}
end

-- Apply the form's infusion to a step's typed damage: its share of every other type becomes the
-- element, scaled by potency. Damage already of the element is left as it is.
function BasicAttackForm.infuse(form: Form, damages: { TypedDamage }): { TypedDamage }
	local infusion = form.infusion
	if not infusion then
		return damages
	end
	local out: { TypedDamage } = {}
	local converted = 0
	for _, entry in ipairs(damages) do
		if entry.type == infusion.element then
			table.insert(out, { type = entry.type, amount = entry.amount })
		else
			local share = entry.amount * infusion.conversion
			converted += share
			if entry.amount - share > 0 then
				table.insert(out, { type = entry.type, amount = entry.amount - share })
			end
		end
	end
	if converted > 0 then
		table.insert(out, { type = infusion.element, amount = converted * infusion.potency })
	end
	return out
end

return BasicAttackForm
