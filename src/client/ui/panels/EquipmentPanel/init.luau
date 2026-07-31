--!strict
-- Container for the equipment panel: reads inventory/equipment state, owns which socket is
-- selected, and hands a plain view model to EquipmentView.
--
-- `script` here IS the EquipmentPanel module (init.luau collapses into its folder), so Parent is
-- `panels` and Parent.Parent is `ui`. EquipmentView, being a child, needs one more level than this.
--
-- Which socket is selected is state this panel owns outright rather than reading from a store (R4
-- allows this as a deliberate, recorded exception): it is presentation-local, nothing outside this
-- panel needs it, and the old runtime (EquipmentPanelRuntime._selectedSlotId) kept it exactly the
-- same way. Selecting a socket still dispatches through MenuOrchestrator so ItemInspectPanel reacts
-- with no extra wiring, matching InventoryPanelPlugin's SET_INSPECT shape.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local useInventory = require(script.Parent.Parent.hooks.useInventory)
local MenuOrchestrator = require(script.Parent.Parent.menu.MenuOrchestrator)
local ItemActions = require(script.Parent.Parent.actions.ItemActions)
local Selector = require(script.Parent.Parent.selectors.equipment)
local EquipmentView = require(script.EquipmentView)

local e = React.createElement

local function EquipmentPanel()
	local inventory = useInventory()
	local selectedSlot, setSelectedSlot = React.useState(nil :: Selector.EquipSlot?)

	local view = Selector.buildView(inventory.inventory, inventory.equipment, inventory.items, selectedSlot)

	-- Clicking a socket selects it and inspects whatever it holds; clicking an empty one clears the
	-- inspect panel, but only if equipment was the thing showing there (mirrors
	-- EquipmentPanelPlugin.bindInspectSelection exactly -- it left another source's inspect alone).
	local function onSlotActivated(slot: Selector.EquipSlot, uid: string?)
		setSelectedSlot(slot)
		if uid then
			MenuOrchestrator.setInspect("equipment", { uid = uid })
			return
		end
		local state = MenuOrchestrator.getState()
		if state.inspect and state.inspect.source == "equipment" then
			MenuOrchestrator.clearInspect()
		end
	end

	-- Clicking a candidate equips it immediately (no carry, no confirm step -- R15 keeps the old
	-- click-to-act model) and selects the socket it landed in, so the paper-doll highlight follows
	-- the item the way EquipmentPanelRuntime's uid-tracked selection used to.
	local function onCandidateActivated(candidate: Selector.CandidateView)
		setSelectedSlot(candidate.targetSlot)
		MenuOrchestrator.setInspect("equipment", { uid = candidate.uid })
		ItemActions.equip(candidate.slotIndex, candidate.targetSlot)
	end

	return e(EquipmentView, {
		view = view,
		selectedSlot = selectedSlot,
		onSlotActivated = onSlotActivated,
		onCandidateActivated = onCandidateActivated,
	})
end

return EquipmentPanel
