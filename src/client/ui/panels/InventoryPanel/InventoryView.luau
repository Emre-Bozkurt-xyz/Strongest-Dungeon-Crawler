--!strict
-- Title row with the fullness count, category tabs, then a scrolling slot grid taking the rest.
--
-- Laid out in logical pixels (PanelRegistry gives this surface `logicalWidth`), which come out at
-- roughly one screen pixel each at 1080p staging, so sizes here are what the player sees. The panel
-- is turned toward the character, so its left edge renders smaller than its right: nothing on the
-- left goes below the theme's `small` step, and the count -- the finest text -- sits on the right.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local PanelShell = require(script.Parent.Parent.Parent.components.PanelShell)
local Header = require(script.Parent.Parent.Parent.components.Header)
local Tabs = require(script.Parent.Parent.Parent.components.Tabs)
local Grid = require(script.Parent.Parent.Parent.components.Grid)
local Slot = require(script.Parent.Parent.Parent.components.Slot)
local ThemeContext = require(script.Parent.Parent.Parent.hooks.ThemeContext)

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

local TITLE_HEIGHT = 34
local TABS_HEIGHT = 32
local CELL = 56
local GAP = 8

local function InventoryView(props: Props)
	local theme = ThemeContext.useTheme()

	local slots: { [string]: any } = {}
	for _, slotView in ipairs(props.view.slots) do
		slots[slotView.key] = e(Slot, {
			icon = slotView.icon,
			rarity = slotView.rarity,
			count = slotView.count,
			selected = slotView.uid ~= nil and slotView.uid == props.selectedUid,
			layoutOrder = slotView.slotIndex,
			onActivated = function()
				props.onSlotActivated(slotView.uid)
			end,
		})
	end

	return e(PanelShell, { padding = 20, gap = 10 }, {
		Title = e("Frame", {
			Size = UDim2.new(1, 0, 0, TITLE_HEIGHT),
			BackgroundTransparency = 1,
			LayoutOrder = 1,
		}, {
			Header = e(Header, { title = "INVENTORY", height = 1 }),
			-- Fullness has to be stated now that the grid only draws items. A fixed grid of empty cells
			-- showed how much room was left; a list that grows cannot.
			Count = e("TextLabel", {
				Text = `{props.view.used} / {props.view.capacity}`,
				FontFace = theme.face.mono,
				TextSize = theme.type.small,
				TextColor3 = theme.color.textMuted,
				Size = UDim2.new(0, 120, 1, 0),
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromScale(1, 0),
				BackgroundTransparency = 1,
				TextXAlignment = Enum.TextXAlignment.Right,
			}),
		}),

		Categories = e(Tabs, {
			tabs = props.categories,
			activeId = props.activeCategory,
			onSelect = props.onCategorySelect,
			layoutOrder = 2,
			heightPx = TABS_HEIGHT,
			textSize = theme.type.small,
		}),

		Grid = e(Grid, {
			layoutOrder = 3,
			fill = true,
			cell = CELL,
			gap = GAP,
			padding = GAP,
			corner = false,
		}, slots),
	})
end

return InventoryView
