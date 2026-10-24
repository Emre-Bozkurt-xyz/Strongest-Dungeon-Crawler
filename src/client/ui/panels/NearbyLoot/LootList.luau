--!strict
-- The list a big pile collapses into: every drop in range as a LootLine row under a count, in a
-- slim System frame that stands over the nearest drop. The wheel moves the selection rather than the
-- list, and the list follows it, so rows past `maxVisibleRows` come into view as they are selected.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local PanelFrame = require(script.Parent.Parent.Parent.components.PanelFrame)
local ThemeContext = require(script.Parent.Parent.Parent.hooks.ThemeContext)
local Selector = require(script.Parent.Parent.Parent.selectors.lootList)
local SharedConfig = require(ReplicatedStorage.Shared.Config)
local LootLine = require(script.Parent.LootLine)

local e = React.createElement

export type Props = {
	view: Selector.LootListView,
	-- Bottom centre of the list, in screen pixels; a binding the container writes every frame.
	position: any,
	onHovered: (uid: string) -> (),
	onActivated: (uid: string) -> (),
	onScrolled: (direction: number) -> (),
}

-- Screen pixels.
local WIDTH = 300
local PADDING = 10
local TITLE_HEIGHT = 22
local ROW_HEIGHT = 30
local ROW_GAP = 2
local SECTION_GAP = 6

local MAX_ROWS = SharedConfig.WorldLootInspect.maxVisibleRows

local LootList = {}

-- The frame's height for `rows` drops, so the container can keep it on screen.
function LootList.height(rows: number): number
	local visible = math.min(rows, MAX_ROWS)
	return PADDING * 2 + TITLE_HEIGHT + SECTION_GAP + visible * ROW_HEIGHT + (visible - 1) * ROW_GAP
end

LootList.WIDTH = WIDTH

local function Row(props: {
	row: Selector.RowView,
	pickupKey: string,
	layoutOrder: number,
	onHovered: (uid: string) -> (),
	onActivated: (uid: string) -> (),
	onScrolled: (direction: number) -> (),
})
	local theme = ThemeContext.useTheme()
	local row = props.row
	local content = LootLine.children(row, props.pickupKey, ROW_HEIGHT, theme)
	content.Padding = e("UIPadding", {
		PaddingLeft = UDim.new(0, 4),
		PaddingRight = UDim.new(0, 6),
	})

	return e("TextButton", {
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		LayoutOrder = props.layoutOrder,
		BackgroundColor3 = theme.color.accent,
		BackgroundTransparency = if row.selected then 0.88 else 1,
		BorderSizePixel = 0,
		[React.Event.MouseEnter] = function()
			props.onHovered(row.uid)
		end,
		[React.Event.Activated] = function()
			props.onActivated(row.uid)
		end,
		[React.Event.InputChanged] = function(_rbx: GuiObject, input: InputObject)
			local direction = LootLine.wheelDirection(input)
			if direction then
				props.onScrolled(direction)
			end
		end,
	}, content)
end

function LootList.render(props: Props)
	local theme = ThemeContext.useTheme()
	local view = props.view
	local scroller = React.useRef(nil :: ScrollingFrame?)

	local selectedIndex = 0
	local rows: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, ROW_GAP),
		}),
	}
	for index, row in ipairs(view.rows) do
		if row.selected then
			selectedIndex = index
		end
		rows[row.uid] = e(Row, {
			row = row,
			pickupKey = view.pickupKey,
			layoutOrder = index,
			onHovered = props.onHovered,
			onActivated = props.onActivated,
			onScrolled = props.onScrolled,
		})
	end

	-- Keeps the selected row in view when the wheel moves past the visible window.
	React.useEffect(function()
		local frame = scroller.current
		if not frame or selectedIndex == 0 then
			return
		end
		local top = (selectedIndex - 1) * (ROW_HEIGHT + ROW_GAP)
		local bottom = top + ROW_HEIGHT
		local viewTop = frame.CanvasPosition.Y
		local viewHeight = frame.AbsoluteWindowSize.Y
		if top < viewTop then
			frame.CanvasPosition = Vector2.new(0, top)
		elseif bottom > viewTop + viewHeight then
			frame.CanvasPosition = Vector2.new(0, bottom - viewHeight)
		end
	end, { selectedIndex })

	local listHeight = LootList.height(#view.rows) - PADDING * 2 - TITLE_HEIGHT - SECTION_GAP

	return e("Frame", {
		Size = UDim2.fromOffset(WIDTH, LootList.height(#view.rows)),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = props.position,
		-- Hidden until the container has placed it once, rather than flashing in the corner.
		Visible = props.position:map(function(position: UDim2)
			return position ~= UDim2.new()
		end),
		BackgroundTransparency = 1,
	}, {
		-- The ambient weight rather than a menu's (R7): this sits over live gameplay, not a dimmed
		-- backdrop, and the menu fill thins out over a bright floor.
		Frame = e(PanelFrame, {
			padding = PADDING,
			gap = SECTION_GAP,
			brackets = "small",
			fillTransparency = theme.styles.AmbientPanel.BackgroundTransparency,
		}, {
			Title = e("Frame", {
				Size = UDim2.new(1, 0, 0, TITLE_HEIGHT),
				LayoutOrder = 1,
				BackgroundTransparency = 1,
			}, {
				Caption = e("TextLabel", {
					Text = "LOOT",
					Size = UDim2.fromScale(0.5, 1),
					BackgroundTransparency = 1,
					FontFace = theme.face.display,
					TextSize = theme.type.small,
					TextColor3 = theme.color.textMuted,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				Count = e("TextLabel", {
					Text = tostring(#view.rows),
					Size = UDim2.fromScale(0.5, 1),
					Position = UDim2.fromScale(0.5, 0),
					BackgroundTransparency = 1,
					FontFace = theme.face.mono,
					TextSize = theme.type.small,
					TextColor3 = theme.color.textMuted,
					TextXAlignment = Enum.TextXAlignment.Right,
				}),
			}),
			Rows = e("ScrollingFrame", {
				Size = UDim2.new(1, 0, 0, listHeight),
				LayoutOrder = 2,
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				CanvasSize = UDim2.new(),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				ScrollingDirection = Enum.ScrollingDirection.Y,
				-- The wheel is the selection's; the list scrolls to follow it instead.
				ScrollingEnabled = false,
				ScrollBarThickness = 2,
				ScrollBarImageColor3 = theme.color.stroke,
				ref = scroller,
			}, rows),
		}),
	})
end

return LootList
