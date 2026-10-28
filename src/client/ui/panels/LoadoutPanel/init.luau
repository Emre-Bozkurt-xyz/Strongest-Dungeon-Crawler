--!strict
-- Container for the Loadout: reads the slot sets, the skills the player has, their combat loadout
-- and progression, owns which set is being edited and which slot is picked, and hands LoadoutView a
-- plain model.
--
-- Assignment is pick-a-slot-then-a-skill rather than drag and drop, so it works the same with a
-- gamepad or a touch screen. Clicking a skill with no slot picked only inspects it. Details open in
-- the side slot (SkillInspectPanel) through the menu's inspect state, as items do.
--
-- `script` here IS the LoadoutPanel module (init.luau collapses into its folder), so Parent is
-- `panels` and Parent.Parent is `ui`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local MasteryTracks = require(ReplicatedStorage.Shared.progression.MasteryTracks)
local MasteryTrees = require(ReplicatedStorage.Shared.progression.MasteryTrees)
local MasteryTree = require(ReplicatedStorage.Shared.progression.MasteryTree)
local PassivePool = require(ReplicatedStorage.Shared.progression.PassivePool)

local SkillSlots = require(script.Parent.Parent.Parent.SkillsFramework.SkillSlots)
local SkillsClient = require(script.Parent.Parent.Parent.SkillsFramework.SkillsClient)
local SkillMetadataClient = require(script.Parent.Parent.Parent.SkillsFramework.SkillMetadataClient)
local ProgressionClient = require(script.Parent.Parent.Parent.Progression.ProgressionClient)
local useCombatLoadout = require(script.Parent.Parent.hooks.useCombatLoadout)
local useProgression = require(script.Parent.Parent.hooks.useProgression)
local useMenuState = require(script.Parent.Parent.hooks.useMenuState)
local MenuOrchestrator = require(script.Parent.Parent.menu.MenuOrchestrator)
local MasteryCanvasController = require(script.Parent.Parent.controllers.MasteryCanvasController)
local UISound = require(script.Parent.Parent.UISound)
local Selector = require(script.Parent.Parent.selectors.loadout)
local LoadoutView = require(script.LoadoutView)

local e = React.createElement

-- Re-renders when the slots, the known skills or their numbers change: none of them is a React
-- store, and each signal only says that something changed.
local function useSkillStores()
	local _, bump = React.useReducer(function(count: number)
		return count + 1
	end, 0)
	React.useEffect(function()
		local function changed()
			bump(nil)
		end
		local offs = {
			SkillSlots.onSlotsChanged(changed),
			SkillSlots.onActiveSetChanged(changed),
			SkillsClient.onKnownChanged(changed),
			SkillMetadataClient.onChanged(changed),
		}
		return function()
			for _, off in ipairs(offs) do
				off()
			end
		end
	end, {})
end

-- The chosen passives as nodes of their trees, so the row draws them as the trees do; then the open
-- slots, then the ones a level has yet to open.
local function passiveCells(progression: ProgressionClient.Snapshot?): { LoadoutView.PassiveCell }
	local cells: { LoadoutView.PassiveCell } = {}
	local open = ProgressionClient.passiveSlots()
	local chosen = ProgressionClient.chosenPassives()
	local context = MasteryCanvasController.context()
	local pairing = if progression
		then MasteryTree.pairingFor(context, progression.shapes, progression.infusion, progression.masteries, progression.attunement)
		else nil
	if pairing then
		pairing.passives = chosen
	end
	for index, level in ipairs(PassivePool.SLOT_LEVELS) do
		if index > open then
			table.insert(cells, { unlocksAt = level })
			continue
		end
		local nodeId = chosen[index]
		local treeDef = if nodeId then select(2, MasteryTrees.node(nodeId)) else nil
		local trackId = if treeDef then treeDef.track else nil
		local node: MasteryTree.Node? = nil
		if nodeId and trackId and progression then
			local tree = MasteryTree.build(
				trackId,
				ProgressionClient.branches(trackId),
				context,
				progression.shapes[context],
				ProgressionClient.isAttuned(trackId),
				pairing
			)
			for _, candidate in ipairs(if tree then tree.nodes else {}) do
				if candidate.id == nodeId then
					node = candidate
				end
			end
		end
		table.insert(cells, { node = node, trackId = trackId })
	end
	return cells
end

local function LoadoutPanel()
	useSkillStores()
	local combat = useCombatLoadout()
	local progression = useProgression()
	local menu = useMenuState()
	local editingSet, setEditingSet = React.useState(SkillSlots.getActiveSet)
	local selectedSlot, setSelectedSlot = React.useState(nil :: number?)

	local limits = SkillSlots.limits()
	if editingSet > limits.sets then
		editingSet = 1
	end
	local inputs: Selector.Inputs = {
		known = SkillsClient.known(),
		slots = SkillSlots.getSet(editingSet),
		limits = limits,
		combat = combat,
		levelOf = ProgressionClient.level,
	}

	local inspect = menu and menu.inspect
	local inspected = if inspect and inspect.source == "loadout" then inspect.payload else nil

	-- Leaving the view lets go of a picked slot.
	local viewing = menu ~= nil and menu.modal.open and menu.modal.view == "loadout"
	React.useEffect(function()
		if not viewing then
			setSelectedSlot(nil)
		end
	end, { viewing })

	local attuned: { string } = {}
	for _, trackId in ipairs(ProgressionClient.attunement()) do
		local track = MasteryTracks.get(trackId)
		table.insert(attuned, if track then track.displayName else trackId)
	end

	local function inspectSkill(skill: string)
		MenuOrchestrator.setInspect("loadout", { kind = "skill", skill = skill, set = editingSet })
	end

	return e(LoadoutView, {
		form = Selector.form(inputs),
		attuned = attuned,
		passives = passiveCells(progression),
		sets = Selector.sets(limits),
		editingSet = editingSet,
		slots = Selector.slots(inputs),
		selectedSlot = selectedSlot,
		library = Selector.library(inputs),
		inspected = inspected,
		onSetSelected = function(set: number)
			UISound.play("confirm")
			setSelectedSlot(nil)
			setEditingSet(set)
			-- The set being edited is the one fought with: one idea, not two.
			SkillSlots.setActiveSet(set)
		end,
		onSlotActivated = function(index: number)
			UISound.play("confirm")
			if selectedSlot == index then
				setSelectedSlot(nil)
				return
			end
			setSelectedSlot(index)
			local skill = inputs.slots and inputs.slots[index]
			if skill and skill ~= "" then
				inspectSkill(skill)
			end
		end,
		onSkillActivated = function(skill: string)
			if selectedSlot then
				UISound.play("slotAssign")
				SkillSlots.assign(selectedSlot, skill, editingSet)
				setSelectedSlot(nil)
			else
				UISound.play("confirm")
			end
			inspectSkill(skill)
		end,
		onFormActivated = function()
			UISound.play("confirm")
			MenuOrchestrator.setInspect("loadout", { kind = "form", set = editingSet })
		end,
		onOpenNode = function(trackId: string, nodeId: string)
			MasteryCanvasController.open(trackId, nil, nodeId)
		end,
	})
end

return LoadoutPanel
