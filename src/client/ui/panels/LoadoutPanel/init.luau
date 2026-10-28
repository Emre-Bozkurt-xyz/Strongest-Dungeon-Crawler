--!strict
-- Container for the Loadout: reads the slot sets, the combat loadout and progression, and the edit in
-- progress (LoadoutEditController, shared with the skills panel beside it), and hands LoadoutView a
-- plain model.
--
-- `script` here IS the LoadoutPanel module (init.luau collapses into its folder), so Parent is
-- `panels` and Parent.Parent is `ui`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local MasteryTracks = require(ReplicatedStorage.Shared.progression.MasteryTracks)
local MasteryTrees = require(ReplicatedStorage.Shared.progression.MasteryTrees)
local MasteryTree = require(ReplicatedStorage.Shared.progression.MasteryTree)
local PassivePool = require(ReplicatedStorage.Shared.progression.PassivePool)
local BasicAttackProfileRegistry = require(ReplicatedStorage.Shared.skills.BasicAttackProfileRegistry)
local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)

local ProgressionClient = require(script.Parent.Parent.Parent.Progression.ProgressionClient)
local useProgression = require(script.Parent.Parent.hooks.useProgression)
local useMenuState = require(script.Parent.Parent.hooks.useMenuState)
local MenuOrchestrator = require(script.Parent.Parent.menu.MenuOrchestrator)
local MasteryCanvasController = require(script.Parent.Parent.controllers.MasteryCanvasController)
local LoadoutEditController = require(script.Parent.Parent.controllers.LoadoutEditController)
local LoadoutDragController = require(script.Parent.Parent.controllers.LoadoutDragController)
local UISound = require(script.Parent.Parent.UISound)
local Selector = require(script.Parent.Parent.selectors.loadout)
local LoadoutView = require(script.LoadoutView)
local useLoadoutInputs = require(script.useLoadoutInputs)

local e = React.createElement

local SKILLS_PANEL = "LoadoutSkillsPanel"

-- The chosen passives as nodes of their trees, so the card draws them as the trees do; then the open
-- slots, then the ones a level has yet to open.
local function passiveCells(
	progression: ProgressionClient.Snapshot?,
	combat: ItemTypes.CombatLoadoutSnapshot?
): { LoadoutView.PassiveCell }
	local cells: { LoadoutView.PassiveCell } = {}
	local open = ProgressionClient.passiveSlots()
	local chosen = ProgressionClient.chosenPassives()
	local context = BasicAttackProfileRegistry.classKeyOf(combat)
	local pairing = if progression
		then MasteryTree.pairingFor(
			context,
			progression.shapes,
			progression.infusion,
			progression.masteries,
			progression.attunement,
			combat
		)
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
	local edit = LoadoutEditController.use()
	local inputs = useLoadoutInputs(edit.editingSet)
	local progression = useProgression()
	local menu = useMenuState()

	-- Leaving the view lets go of a picked slot, a held skill and a drag.
	local viewing = menu ~= nil and menu.modal.open and menu.modal.view == "loadout"
	React.useEffect(function()
		if not viewing then
			LoadoutDragController.cancel()
			LoadoutEditController.reset()
		end
	end, { viewing })

	local attuned: { string } = {}
	for _, trackId in ipairs(ProgressionClient.attunement()) do
		local track = MasteryTracks.get(trackId)
		table.insert(attuned, if track then track.displayName else trackId)
	end

	local skillsShown = menu == nil or menu.contextPanels[SKILLS_PANEL] ~= false
	local picked = edit.picked

	return e(LoadoutView, {
		form = Selector.form(inputs),
		attuned = attuned,
		passives = passiveCells(progression, inputs.combat),
		sets = Selector.sets(inputs.limits),
		editingSet = edit.editingSet,
		slots = Selector.slots(inputs),
		picked = picked,
		dropSlot = edit.dropSlot,
		heldName = if edit.held then Selector.displayNameOf(edit.held) else nil,
		skillsShown = skillsShown,
		onToggleSkills = function()
			UISound.play("confirm")
			MenuOrchestrator.setContextPanel(SKILLS_PANEL, not skillsShown)
		end,
		onSetSelected = LoadoutEditController.setEditingSet,
		onSlotActivated = LoadoutEditController.activateSlot,
		onClearPicked = function()
			if picked then
				LoadoutEditController.clear(picked)
			end
		end,
		onOpenNode = function(trackId: string?, nodeId: string?)
			MasteryCanvasController.open(trackId, nil, nodeId)
		end,
	})
end

return LoadoutPanel
