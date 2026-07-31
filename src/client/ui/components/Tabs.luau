--!strict
-- Horizontal tab strip. The inventory's category bar.
--
-- Controlled: the caller owns which tab is active and is told when one is picked. Tabs hold no
-- state of their own, so the same strip works whether selection lives in a component, the menu
-- store, or a URL-ish route later.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ThemeContext = require(script.Parent.Parent.hooks.ThemeContext)
local Panel = require(script.Parent.Panel)
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
	height: number?,
	-- Canvas pixels. Uniform across tabs regardless of label length.
	textSize: number?,
}

local function Tabs(props: Props)
	local theme = ThemeContext.useTheme()

	local children: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, theme.metrics.paddingSm),
		}),
	}

	-- Equal shares of the bar rather than auto-sizing to the label. A TextButton with AutomaticSize.X
	-- holding a label sized to its parent is circular -- the button waits on the label's width and the
	-- label waits on the button's -- and Roblox resolves it to near-zero, which renders the text as
	-- specks. Equal shares also space the tabs evenly, which the Studio bar did not.
	local share = 1 / math.max(#props.tabs, 1)

	for index, tab in ipairs(props.tabs) do
		local active = tab.id == props.activeId
		children[tab.id] = e("TextButton", {
			Text = "",
			LayoutOrder = index,
			Size = UDim2.fromScale(share, 1),
			BackgroundTransparency = 1,
			[React.Event.Activated] = function()
				if props.onSelect then
					props.onSelect(tab.id)
				end
			end,
		}, {
			Label = e(Text, {
				text = tab.label,
				role = if active then "TabActive" else "TabInactive",
				size = UDim2.fromScale(1, 0.75),
				position = UDim2.fromScale(0.5, 0.5),
				anchorPoint = Vector2.new(0.5, 0.5),
				alignX = Enum.TextXAlignment.Center,
				-- Fixed rather than scaled: scaling to the box would size each label by how long its
				-- word happens to be, so "All" would tower over "Consumable".
				textSize = props.textSize or 26,
				glow = active,
			}),
		})
	end

	return e(Panel, {
		stroke = true,
		layoutOrder = props.layoutOrder,
		size = UDim2.new(1, 0, props.height or 0.11, 0),
		padding = theme.metrics.paddingSm,
		props = { BackgroundTransparency = 1 },
	}, children)
end

return Tabs
