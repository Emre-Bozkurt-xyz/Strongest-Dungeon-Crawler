--!strict
-- Container for the inventory panel: reads inventory state, owns which category tab is active and
-- which slot is selected, and hands a plain view model to InventoryView.
--
-- `script` here IS the InventoryPanel module (init.luau collapses into its folder), so Parent is
-- `panels` and Parent.Parent is `ui`. InventoryView, being a child, needs one more level than this.
--
-- Category and selection are both presentation-local state (R4's recorded exception -- the same call
-- EquipmentPanel made for its selected socket): nothing outside this panel needs either, and the old
-- runtime (InventoryMenuRuntime.selectedCategory/selectedUid) kept them exactly the same way. Picking
-- a slot still dispatches through MenuOrchestrator so ItemInspectPanel reacts with no extra wiring --
-- the same SET_INSPECT/CLEAR_INSPECT shape InventoryPanelPlugin.bindInspectSelection used, clearing
-- only when the inspect panel is currently showing something this panel put there.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local useInventory = require(script.Parent.Parent.hooks.useInventory)
local MenuOrchestrator = require(script.Parent.Parent.menu.MenuOrchestrator)
local Selector = require(script.Parent.Parent.selectors.inventory)
local InventoryView = require(script.InventoryView)

local e = React.createElement

local CATEGORY_TABS = {}
for _, id in ipairs(Selector.CATEGORIES) do
	table.insert(CATEGORY_TABS, { id = id, label = id:sub(1, 1):upper() .. id:sub(2) })
end

local function clearInventoryInspect()
	local state = MenuOrchestrator.getState()
	if state.inspect and state.inspect.source == "inventory" then
		MenuOrchestrator.clearInspect()
	end
end

local function InventoryPanel()
	local inventory = useInventory()
	local activeCategory, setActiveCategory = React.useState("all" :: Selector.Category)
	local selectedUid, setSelectedUid = React.useState(nil :: string?)

	local view = Selector.buildView(inventory.inventory, inventory.items, activeCategory)

	-- Mirrors InventoryMenuRuntime:refresh's guard: a selection that no longer resolves to a visible
	-- slot -- dropped, consumed, or filtered out by a tab switch -- stops being selected, and clears
	-- the inspect panel if it was the thing showing there.
	React.useEffect(function()
		if not selectedUid then
			return
		end
		for _, slot in ipairs(view.slots) do
			if slot.uid == selectedUid then
				return
			end
		end
		setSelectedUid(nil)
		clearInventoryInspect()
	end, { selectedUid, activeCategory, inventory })

	local function onSlotActivated(uid: string?)
		setSelectedUid(uid)
		if uid then
			MenuOrchestrator.setInspect("inventory", { uid = uid })
		else
			clearInventoryInspect()
		end
	end

	return e(InventoryView, {
		view = view,
		categories = CATEGORY_TABS,
		activeCategory = activeCategory,
		onCategorySelect = function(id: string)
			setActiveCategory(id :: Selector.Category)
		end,
		selectedUid = selectedUid,
		onSlotActivated = onSlotActivated,
	})
end

return InventoryPanel
