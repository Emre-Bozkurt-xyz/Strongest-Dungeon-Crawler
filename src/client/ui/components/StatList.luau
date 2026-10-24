--!strict
-- Titled groups of label/value rows: the item card's details and the System panel's stats.
--
-- Laid out in pixels for logical-width surfaces. Rows put the label in the body face and the value
-- in mono, like every other ticking value; mono also holds up at distance better than the narrow
-- body face.
--
-- Alternate rows carry a faint band. Menu panels are seen in perspective, which slopes a row the
-- lower it sits on the panel, so a value at the far end can look level with the next row's label;
-- the band shows which line it is on.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ThemeContext = require(script.Parent.Parent.hooks.ThemeContext)
local Text = require(script.Parent.Text)

local e = React.createElement

local StatList = {}

local DEFAULT_ROW_HEIGHT = 26
local ROW_GAP = 2
local HEADING_HEIGHT = 22
local DEFAULT_LABEL_WIDTH = 0.58

-- Pixel height of a section holding `rows` rows, for a parent that lays sections out by hand.
function StatList.height(rows: number, rowHeight: number?): number
	return HEADING_HEIGHT + rows * ((rowHeight or DEFAULT_ROW_HEIGHT) + ROW_GAP)
end

-- A titled group. One real container rather than a Fragment, so the section has an Instance of its
-- own to lay out, and children merge in flat.
--
-- Height is computed rather than left to AutomaticSize. Sections can sit inside a ScrollingFrame
-- with AutomaticCanvasSize that is itself sized by UIFlexItem, and an auto-sized child in that chain
-- makes the constraint circular -- Roblox resolves it inconsistently, which showed up as label and
-- value columns drifting further apart the further down the list they were.
function StatList.Section(props: { title: string, layoutOrder: number?, rowHeight: number?, children: any })
	local theme = ThemeContext.useTheme()
	local children: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, ROW_GAP),
		}),
		Heading = e(Text, {
			text = string.upper(props.title),
			role = "MutedText",
			layoutOrder = 0,
			size = UDim2.new(1, 0, 0, HEADING_HEIGHT),
			textSize = theme.type.small,
			props = { FontFace = theme.face.display },
		}),
	}
	local rowCount = 0
	for key, child in pairs(props.children or {}) do
		children[key] = child
		rowCount += 1
	end

	return e("Frame", {
		LayoutOrder = props.layoutOrder,
		Size = UDim2.new(1, 0, 0, StatList.height(rowCount, props.rowHeight)),
		BackgroundTransparency = 1,
	}, children)
end

-- A label/value row. `role` carries the semantics: an unmet requirement is RequirementUnmet, which
-- is where the theme's danger colour enters (Guardrail 3 -- no colour literals here).
function StatList.Row(props: {
	label: string,
	value: string,
	role: any,
	layoutOrder: number?,
	rowHeight: number?,
	labelWidth: number?,
})
	local theme = ThemeContext.useTheme()
	local labelWidth = props.labelWidth or DEFAULT_LABEL_WIDTH
	local banded = (props.layoutOrder or 0) % 2 == 0
	return e("Frame", {
		LayoutOrder = props.layoutOrder,
		Size = UDim2.new(1, 0, 0, props.rowHeight or DEFAULT_ROW_HEIGHT),
		BackgroundColor3 = theme.color.textPrimary,
		BackgroundTransparency = if banded then 0.95 else 1,
		BorderSizePixel = 0,
	}, {
		-- Inset so text clears the band's ends.
		Padding = e("UIPadding", {
			PaddingLeft = UDim.new(0, 4),
			PaddingRight = UDim.new(0, 4),
		}),
		Label = e(Text, {
			text = props.label,
			role = props.role,
			size = UDim2.fromScale(labelWidth, 1),
			textSize = theme.type.body,
		}),
		Value = e(Text, {
			text = props.value,
			role = props.role,
			size = UDim2.fromScale(1 - labelWidth, 1),
			position = UDim2.fromScale(labelWidth, 0),
			alignX = Enum.TextXAlignment.Right,
			textSize = theme.type.small,
			props = { FontFace = theme.face.mono },
		}),
	})
end

return StatList
