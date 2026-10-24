--!strict
-- Horizontal tab strip. The inventory's category bar.
--
-- Controlled: the caller owns which tab is active and is told when one is picked. Tabs hold no
-- state of their own, so the same strip works whether selection lives in a component, the menu
-- store, or a URL-ish route later.
--
-- The active tab is marked by a line of light under its label, sitting on a dim hairline that runs
-- the width of the strip -- the same language as the header underline, rather than a boxed bar.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ThemeContext = require(script.Parent.Parent.hooks.ThemeContext)
local UISound = require(script.Parent.Parent.UISound)
local Text = require(script.Parent.Text)

local e = React.createElement

export type Tab = {
	id: string,
	label: string,
}

export type Props = {
	tabs: { Tab },
	activeId: string?,
	onSelect: ((id: string) -> ())?,
	layoutOrder: number?,
	-- Scale height within a scale-laid-out panel, or `heightPx` for a logical-pixel one.
	height: number?,
	heightPx: number?,
	-- Pixels. Uniform across tabs regardless of label length.
	textSize: number?,
}

local function Tabs(props: Props)
	local theme = ThemeContext.useTheme()

	local row: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		}),
	}

	-- Equal shares of the strip rather than auto-sizing to the label. A TextButton with
	-- AutomaticSize.X holding a label sized to its parent is circular, and Roblox resolves it to
	-- near-zero, which renders the text as specks. Equal shares also space the tabs evenly.
	local share = 1 / math.max(#props.tabs, 1)

	for index, tab in ipairs(props.tabs) do
		local active = tab.id == props.activeId
		row[tab.id] = e("TextButton", {
			Text = "",
			LayoutOrder = index,
			Size = UDim2.fromScale(share, 1),
			BackgroundTransparency = 1,
			[React.Event.Activated] = function()
				if props.onSelect then
					UISound.play("confirm")
					props.onSelect(tab.id)
				end
			end,
		}, {
			Label = e(Text, {
				text = string.upper(tab.label),
				role = if active then "TabActive" else "TabInactive",
				size = UDim2.fromScale(1, 0.8),
				alignX = Enum.TextXAlignment.Center,
				-- Fixed rather than scaled: scaling to the box would size each label by how long its
				-- word happens to be, so "All" would tower over "Consumable".
				textSize = props.textSize or theme.type.small,
			}),
			Mark = if active
				then e("Frame", {
					Size = UDim2.new(0.6, 0, 0, theme.metrics.strokeThick),
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.fromScale(0.5, 1),
					BackgroundColor3 = theme.color.strokeStrong,
					BorderSizePixel = 0,
				})
				else nil,
		})
	end

	return e("Frame", {
		LayoutOrder = props.layoutOrder,
		Size = if props.heightPx
			then UDim2.new(1, 0, 0, props.heightPx)
			else UDim2.new(1, 0, props.height or 0.11, 0),
		BackgroundTransparency = 1,
	}, {
		Row = e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, row),
		Hairline = e("Frame", {
			Size = UDim2.new(1, 0, 0, 1),
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			BackgroundColor3 = theme.color.stroke,
			BackgroundTransparency = 0.7,
			BorderSizePixel = 0,
		}),
	})
end

return Tabs
