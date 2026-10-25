--!strict
-- Title row with the fullness count, category tabs, then the slot grid.
--
-- The panel is as tall as its rows (a `fitContent` surface): a light bag is a short panel that grows
-- as it fills, rather than one row floating at the top of a tall empty one. It never drops below
-- MIN_ROWS, so switching to a sparse category does not collapse it to a sliver, and stops at what the
-- surface holds, past which the grid scrolls.
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
local PADDING = 20
local STACK_GAP = 10

-- The surface, in logical pixels (PanelRegistry: 768 across, 6.478 x 3.549 studs).
local LOGICAL_WIDTH = 768
local LOGICAL_HEIGHT = math.floor(768 * 3.549 / 6.478)

local CHROME_HEIGHT = 2 * PADDING + TITLE_HEIGHT + STACK_GAP + TABS_HEIGHT + STACK_GAP
local COLUMNS = math.floor((LOGICAL_WIDTH - 2 * PADDING - 2 * GAP + GAP) / (CELL + GAP))
local MIN_ROWS = 2

local function gridHeight(rows: number): number
	return rows * CELL + (rows - 1) * GAP + 2 * GAP
end

local MAX_ROWS = math.floor((LOGICAL_HEIGHT - CHROME_HEIGHT - 2 * GAP + GAP) / (CELL + GAP))

local function InventoryView(props: Props)
	local theme = ThemeContext.useTheme()

	local slots: { [string]: any } = {}
	for _, slotView in ipairs(props.view.slots) do
		slots[slotView.key] = e(Slot, {
			icon = slotView.icon,
			glyph = slotView.glyph,
			rarity = slotView.rarity,
			count = slotView.count,
			selected = slotView.uid ~= nil and slotView.uid == props.selectedUid,
			layoutOrder = slotView.slotIndex,
			onActivated = function()
				props.onSlotActivated(slotView.uid)
			end,
		})
	end

	local rows = math.clamp(math.ceil(#props.view.slots / COLUMNS), MIN_ROWS, MAX_ROWS)

	return e(PanelShell, { padding = PADDING, gap = STACK_GAP, height = CHROME_HEIGHT + gridHeight(rows) }, {
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
