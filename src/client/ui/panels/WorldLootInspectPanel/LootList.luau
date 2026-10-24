--!strict
-- Title over a scrolling list of nearby drops.
--
-- A single AmbientPanel (R7) rather than PanelShell's backdrop+body: this surface shows during play,
-- next to loot on the ground, so it competes with the world behind it rather than a dimmed backdrop.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local Panel = require(script.Parent.Parent.Parent.components.Panel)
local Header = require(script.Parent.Parent.Parent.components.Header)
local ScrollList = require(script.Parent.Parent.Parent.components.ScrollList)
local ThemeContext = require(script.Parent.Parent.Parent.hooks.ThemeContext)

local Selector = require(script.Parent.Parent.Parent.selectors.lootList)
local LootRow = require(script.Parent.LootRow)

local SharedConfig = require(ReplicatedStorage.Shared.Config)

local e = React.createElement

export type Props = {
	view: Selector.LootListView,
	onRowHovered: (uid: string) -> (),
	onRowActivated: (uid: string) -> (),
}

-- Canvas pixels. PanelRegistry puts this surface at 2.874 studs tall and 400 px/stud. Rows have to be
-- sized in offset -- scale inside an auto-sizing ScrollingFrame resolves against the canvas it is
-- growing -- so the row height is derived from the surface instead, to fit `maxVisibleRows` rows
-- before the list starts scrolling.
local CANVAS_HEIGHT = math.floor(2.874 * 400)
local HEADER_HEIGHT = 0.1
local VISIBLE_ROWS = SharedConfig.WorldLootInspect.maxVisibleRows

local function LootList(props: Props)
	local theme = ThemeContext.useTheme()
	local metrics = theme.metrics

	local content = CANVAS_HEIGHT - 2 * metrics.paddingLg
	local listHeight = content * (1 - HEADER_HEIGHT) - metrics.paddingMd - 2 * metrics.paddingSm
	local rowGap = metrics.paddingSm
	local rowHeight = math.floor((listHeight - (VISIBLE_ROWS - 1) * rowGap) / VISIBLE_ROWS)

	local rows: { [string]: any } = {}
	for index, row in ipairs(props.view.rows) do
		rows[`Row_{row.uid}`] = e(LootRow, {
			row = row,
			pickupKey = props.view.pickupKey,
			height = rowHeight,
			layoutOrder = index,
			onHovered = props.onRowHovered,
			onActivated = props.onRowActivated,
		})
	end

	return e(Panel, {
		role = "AmbientPanel",
		stroke = true,
		padding = metrics.paddingLg,
	}, {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, metrics.paddingMd),
		}),
		Title = e(Header, { title = props.view.title, layoutOrder = 1, height = HEADER_HEIGHT }),
		List = e(ScrollList, {
			layoutOrder = 2,
			fill = true,
			gap = rowGap,
			padding = metrics.paddingSm,
		}, rows),
	})
end

return LootList
