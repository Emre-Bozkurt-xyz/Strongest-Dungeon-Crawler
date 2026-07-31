--!strict
-- Title, category tab bar, then a scrolling slot grid absorbing the rest of the panel.
--
-- Ported from docs/ui/InventoryPanel.rbxmx. Unlike EquipmentPanel this export is a genuine vertical
-- stack -- Header, CategoryBar, InventoryGrid, in that LayoutOrder -- so PanelShell's default "stack"
-- layout applies directly instead of the free-positioned columns EquipmentPanel needed.
--
-- The export's tab bar spaces its buttons with a plain UIListLayout and no padding, so two labels
-- ("Equipment", "Consumable") visibly run together in the screenshot. Tabs lays out with even
-- padding between labels instead, which fixes that without changing anything else about the bar
-- (R12's licensed improvement).
--
-- The export's ItemSlotTemplate nests a full-size RarityFrame behind a smaller (0.85 scale) Content
-- frame, so a rarity colour only ever shows as a ring around the darker centre rather than a filled
-- square -- that is exactly Slot's own outer-frame/Inset nesting, so `tint` on Slot already reproduces
-- it with no primitive change needed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local PanelShell = require(script.Parent.Parent.Parent.components.PanelShell)
local Header = require(script.Parent.Parent.Parent.components.Header)
local Text = require(script.Parent.Parent.Parent.components.Text)
local Tabs = require(script.Parent.Parent.Parent.components.Tabs)
local Grid = require(script.Parent.Parent.Parent.components.Grid)
local Slot = require(script.Parent.Parent.Parent.components.Slot)

local Selector = require(script.Parent.Parent.Parent.selectors.inventory)

local e = React.createElement

export type Props = {
	view: Selector.InventoryGridView,
	categories: { Tabs.Tab },
	activeCategory: string,
	onCategorySelect: (id: string) -> (),
	selectedUid: string?,
	onSlotActivated: (uid: string?) -> (),
}

-- Canvas pixels. The export's grid is 150px cells, 30px gaps and 50px padding on its authored
-- 1920-wide canvas (docs/ui/InventoryPanel.rbxmx: SurfaceGui CanvasSize = 1920x1080). PanelRegistry
-- puts this surface at 6.478 studs wide and 200 px/stud (matching SystemPanel), so the real canvas is
-- narrower than the design canvas -- this ratio is what has to survive, not the raw pixel counts.
local SCALE = (6.478 * 200) / 1920
local CELL = math.floor(150 * SCALE + 0.5)
local GAP = math.floor(30 * SCALE + 0.5)
local GRID_PADDING = math.floor(50 * SCALE + 0.5)

local function InventoryView(props: Props)
	local slots: { [string]: any } = {}
	for _, slotView in ipairs(props.view.slots) do
		slots[slotView.key] = e(Slot, {
			icon = slotView.icon,
			tint = slotView.tint,
			count = slotView.count,
			selected = slotView.uid ~= nil and slotView.uid == props.selectedUid,
			layoutOrder = slotView.slotIndex,
			onActivated = function()
				props.onSlotActivated(slotView.uid)
			end,
		})
	end

	return e(PanelShell, nil, {
		Title = e(Header, { title = "INVENTORY", layoutOrder = 1 }),

		-- Fullness has to be stated now that the grid only draws items. A fixed grid of empty cells
		-- showed how much room was left; a list that grows cannot.
		Counter = e(Text, {
			text = `{props.view.used} / {props.view.capacity}`,
			role = "MutedText",
			layoutOrder = 2,
			size = UDim2.new(1, 0, 0.05, 0),
			alignX = Enum.TextXAlignment.Right,
			textSize = 22,
		}),

		Categories = e(Tabs, {
			tabs = props.categories,
			activeId = props.activeCategory,
			onSelect = props.onCategorySelect,
			layoutOrder = 3,
		}),

		Grid = e(Grid, {
			layoutOrder = 4,
			fill = true,
			cell = CELL,
			gap = GAP,
			padding = GRID_PADDING,
			stroke = true,
		}, slots),
	})
end

return InventoryView
