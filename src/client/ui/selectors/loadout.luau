--!strict
-- The Loadout view's model (docs/planning/progression-direction.md, "Loadout"): the basic attack's
-- form, the slots of the set being edited, and every skill the player has, grouped by the mastery it
-- comes from.
--
-- Pure: the container reads the stores and passes them in.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientSpec = require(ReplicatedStorage.Shared.skills.ClientSpec)
local LoadoutTypes = require(ReplicatedStorage.Shared.skills.LoadoutTypes)
local LoadoutUnlocks = require(ReplicatedStorage.Shared.skills.LoadoutUnlocks)
local BasicAttackForm = require(ReplicatedStorage.Shared.skills.BasicAttackForm)
local SkillRequirementResolver = require(ReplicatedStorage.Shared.skills.SkillRequirementResolver)
local MasteryTracks = require(ReplicatedStorage.Shared.progression.MasteryTracks)
local MasteryTrees = require(ReplicatedStorage.Shared.progression.MasteryTrees)
local Registry = require(ReplicatedStorage.Shared.items.Registry)
local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)

local SkillMetadataClient = require(script.Parent.Parent.Parent.SkillsFramework.SkillMetadataClient)
local SlotSelector = require(script.Parent.skillSlots)
local skillLook = require(script.Parent.skillLook)

local Selector = {}

-- The skill that plays the basic attack's form. It is a skill like any other in the slots, so it can
-- sit in any of them.
Selector.BASIC_ATTACK = "BasicAttack"

-- Skills from no mastery: movement and the basic attack.
local GENERAL = "GENERAL"

export type Look = skillLook.Look

export type SkillView = {
	name: string,
	displayName: string,
	look: Look,
	-- "6 Mana · 1.5s", or the reason it does not fit the held weapon.
	subtitle: string,
	-- Why the held weapon cannot use it, nil when it can.
	misfit: string?,
	-- The slot it sits in, in the set being edited.
	slot: number?,
	track: string?,
}

export type SkillGroup = {
	id: string,
	label: string,
	-- The mastery's level, for a group from one.
	level: number?,
	skills: { SkillView },
}

export type SlotView = {
	index: number,
	keyLabel: string,
	-- The level that opens it, while it is locked.
	unlocksAt: number?,
	skill: SkillView?,
}

export type SetView = {
	index: number,
	unlocksAt: number?,
}

export type FormView = {
	displayName: string,
	weaponName: string,
	weaponGlyph: string,
	look: Look,
	shape: { name: string, node: string?, track: string? },
	infusion: { name: string, node: string, track: string? }?,
	combination: string?,
	-- "4 Mana" per step, plus any second resource.
	cost: string,
	-- "100% Physical", or the split an infusion makes.
	damage: string,
	scaling: string?,
	-- Each step's damage multiplier, for the combo's shape.
	steps: { number },
	-- Which slot holds the basic attack, in the set being edited.
	slot: number?,
	description: string,
}

export type Inputs = {
	known: { string },
	slots: { string }?,
	limits: LoadoutUnlocks.Limits,
	combat: ItemTypes.CombatLoadoutSnapshot?,
	levelOf: (trackId: string) -> number,
}

local function trimNumber(value: number): string
	local rounded = math.floor(value * 10 + 0.5) / 10
	return if rounded == math.floor(rounded) then tostring(math.floor(rounded)) else tostring(rounded)
end

local function listOf(items: { string }): string
	if #items <= 1 then
		return items[1] or ""
	end
	return table.concat(items, ", ", 1, #items - 1) .. " or " .. items[#items]
end

-- Why the held weapon cannot use `skill`, in words; nil when it can.
function Selector.misfitOf(skill: string, combat: ItemTypes.CombatLoadoutSnapshot?): string?
	local metadata = SkillMetadataClient.get(skill)
	local requirement = metadata and metadata.requirements and metadata.requirements.weapon
	if not requirement then
		return nil
	end
	local ok, reason = SkillRequirementResolver.evaluate(requirement, combat)
	if ok then
		return nil
	end
	if reason == "wrong_weapon_class" and requirement.classes then
		local names: { string } = {}
		for _, class in ipairs(requirement.classes) do
			table.insert(names, `a {class}`)
		end
		return `Needs {listOf(names)}`
	elseif reason == "requires_weapon" then
		return "Needs a weapon"
	elseif reason == "requires_shield" then
		return "Needs a shield"
	end
	return "Does not fit what you hold"
end

local function subtitleOf(skill: string): string
	local metadata = SkillMetadataClient.get(skill)
	if not metadata then
		return ""
	end
	local parts: { string } = {}
	if metadata.cost and metadata.cost > 0 then
		table.insert(parts, `{trimNumber(metadata.cost)} {metadata.costResource or ""}`)
	end
	if metadata.cooldown and metadata.cooldown > 0 then
		table.insert(parts, `{trimNumber(metadata.cooldown)}s`)
	end
	return table.concat(parts, "  ·  ")
end

function Selector.displayNameOf(skill: string): string
	local spec = ClientSpec[skill]
	return if spec and type(spec.label) == "string" then spec.label else skill
end

function Selector.skillView(skill: string, inputs: Inputs, form: BasicAttackForm.Form?): SkillView
	local spec = ClientSpec[skill]
	local misfit = Selector.misfitOf(skill, inputs.combat)
	local slot = if inputs.slots then table.find(inputs.slots, skill) else nil
	return {
		name = skill,
		displayName = Selector.displayNameOf(skill),
		look = skillLook(skill, inputs.combat),
		subtitle = misfit or (if skill == Selector.BASIC_ATTACK and form then form.displayName else subtitleOf(skill)),
		misfit = misfit,
		slot = if slot and slot <= inputs.limits.slots then slot else nil,
		track = if spec and spec.mastery then spec.mastery.track else nil,
	}
end

function Selector.form(inputs: Inputs): FormView
	local form = BasicAttackForm.resolve(inputs.combat)
	local main = inputs.combat and inputs.combat.main
	local def = main and Registry.get(main.itemId)

	local shapeDef, shapeTree = nil, nil
	if form.shapeNode then
		shapeDef, shapeTree = MasteryTrees.node(form.shapeNode)
	end
	local infusion = form.infusion
	local infusionTree = if infusion then select(2, MasteryTrees.node(infusion.id)) else nil

	local amounts: { string } = {}
	for _, amount in ipairs(form.cost.steps) do
		table.insert(amounts, trimNumber(amount))
	end
	local cost = `{table.concat(amounts, " / ")} {form.cost.resource}`
	for _, extra in ipairs(form.cost.extra) do
		cost ..= `  +  {trimNumber(extra.steps[1] or 0)} {extra.resource}`
	end

	local baseType = if main and main.damage[1] then main.damage[1].type else "Physical"
	local damage = `100% {baseType}`
	if infusion then
		local converted = math.floor(infusion.conversion * 100 + 0.5)
		damage = `{100 - converted}% {baseType}  ·  {converted}% {infusion.element}`
	end

	local scaling: string? = nil
	if shapeDef and shapeDef.attributes then
		local parts: { string } = {}
		for attribute, tier in pairs(shapeDef.attributes) do
			table.insert(parts, `{string.upper(attribute)} {string.upper(tier)}`)
		end
		table.sort(parts)
		scaling = table.concat(parts, "  ·  ")
	end

	local steps: { number } = {}
	for _, step in ipairs(form.profile.steps) do
		table.insert(steps, step.damageMultiplier)
	end

	local slot = if inputs.slots then table.find(inputs.slots, Selector.BASIC_ATTACK) else nil
	return {
		displayName = form.displayName,
		weaponName = if def then def.name else "Bare hands",
		weaponGlyph = if main then main.weaponClass else "fist",
		look = { art = form.shapeNode, glyph = if main then main.weaponClass else "fist" },
		shape = {
			name = if shapeDef then shapeDef.displayName else form.profile.displayName,
			node = form.shapeNode,
			track = if shapeTree then shapeTree.track else nil,
		},
		infusion = if infusion
			then {
				name = infusion.displayName,
				node = infusion.id,
				track = if infusionTree then infusionTree.track else nil,
			}
			else nil,
		combination = if form.combination then form.combination.displayName else nil,
		cost = cost,
		damage = damage,
		scaling = scaling,
		steps = steps,
		slot = if slot and slot <= inputs.limits.slots then slot else nil,
		description = if shapeDef then shapeDef.description else "",
	}
end

function Selector.slots(inputs: Inputs): { SlotView }
	local form = BasicAttackForm.resolve(inputs.combat)
	local out: { SlotView } = {}
	for index = 1, LoadoutTypes.SLOTS_PER_SET do
		local level = LoadoutUnlocks.SLOT_LEVELS[index]
		local skill = inputs.slots and inputs.slots[index]
		local open = index <= inputs.limits.slots
		table.insert(out, {
			index = index,
			keyLabel = SlotSelector.keyLabelFor(index) or tostring(index),
			unlocksAt = if open then nil else level,
			skill = if open and skill and skill ~= LoadoutTypes.EMPTY
				then Selector.skillView(skill, inputs, form)
				else nil,
		})
	end
	return out
end

function Selector.sets(limits: LoadoutUnlocks.Limits): { SetView }
	local out: { SetView } = {}
	for index = 1, LoadoutTypes.MAX_SETS do
		table.insert(out, {
			index = index,
			unlocksAt = if index <= limits.sets then nil else LoadoutUnlocks.SET_LEVELS[index],
		})
	end
	return out
end

-- Every skill the player has: the masteries' groups in track order, then the rest.
function Selector.library(inputs: Inputs): { SkillGroup }
	local form = BasicAttackForm.resolve(inputs.combat)
	local byGroup: { [string]: { SkillView } } = {}
	for _, skill in ipairs(inputs.known) do
		local view = Selector.skillView(skill, inputs, form)
		local group = view.track or GENERAL
		byGroup[group] = byGroup[group] or {}
		table.insert(byGroup[group], view)
	end

	local groups: { SkillGroup } = {}
	local function sorted(list: { SkillView }): { SkillView }
		table.sort(list, function(a, b)
			-- The basic attack leads its group: it is the one every build has.
			if (a.name == Selector.BASIC_ATTACK) ~= (b.name == Selector.BASIC_ATTACK) then
				return a.name == Selector.BASIC_ATTACK
			end
			return a.displayName < b.displayName
		end)
		return list
	end
	for _, track in ipairs(MasteryTracks.list()) do
		local list = byGroup[track.id]
		if list then
			table.insert(groups, {
				id = track.id,
				label = string.upper(track.displayName),
				level = inputs.levelOf(track.id),
				skills = sorted(list),
			})
		end
	end
	if byGroup[GENERAL] then
		table.insert(groups, { id = GENERAL, label = GENERAL, skills = sorted(byGroup[GENERAL]) })
	end
	return groups
end

return Selector
