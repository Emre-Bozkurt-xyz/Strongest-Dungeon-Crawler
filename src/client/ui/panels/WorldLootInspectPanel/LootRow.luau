--!strict
-- One nearby drop: rarity-tinted slot, the item name in its rarity colour, and on the selected row a
-- pickup key hint.
--
-- Selection is carried by the row's own outline -- brighter and heavier when selected. Panel's
-- `stroke` is fixed to the theme's resting colour, so the outline is built here instead. An overlay
-- would have to sit above the slot to be seen, and then it covers the item it is highlighting.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local Panel = require(script.Parent.Parent.Parent.components.Panel)
local Slot = require(script.Parent.Parent.Parent.components.Slot)
local Text = require(script.Parent.Parent.Parent.components.Text)
local ThemeContext = require(script.Parent.Parent.Parent.hooks.ThemeContext)

local Selector = require(script.Parent.Parent.Parent.selectors.lootList)

local e = React.createElement

export type Props = {
	row: Selector.RowView,
	pickupKey: string,
	-- Canvas pixels; LootList sizes rows so a configured number fit before the list scrolls.
	height: number,
	layoutOrder: number,
	onHovered: (uid: string) -> (),
	onActivated: (uid: string) -> (),
}

local function LootRow(props: Props)
	local theme = ThemeContext.useTheme()
	local row = props.row
	local selected = row.selected
	local pad = theme.metrics.paddingSm
	local iconSize = props.height - 2 * pad
	local labelInset = iconSize + theme.metrics.paddingMd

	return e(Panel, {
		role = "PanelBlock",
		size = UDim2.new(1, 0, 0, props.height),
		layoutOrder = props.layoutOrder,
		padding = pad,
		props = if selected then { BackgroundTransparency = 0.4 } else nil,
	}, {
		Outline = e("UIStroke", {
			Color = if selected then theme.color.strokeStrong else theme.color.stroke,
			Thickness = if selected then theme.metrics.strokeThick else theme.metrics.strokeThin,
			Transparency = if selected then 0.1 else 0.6,
		}),

		Slot = e(Slot, {
			icon = row.icon,
			rarity = row.rarity,
			count = row.count,
			selected = selected,
			size = UDim2.fromOffset(iconSize, iconSize),
			anchorPoint = Vector2.new(0, 0.5),
			position = UDim2.fromScale(0, 0.5),
		}),

		Label = e("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(labelInset, 0),
			Size = UDim2.new(1, -labelInset, 1, 0),
		}, {
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			Name = e(Text, {
				text = row.name,
				role = "BodyText",
				size = UDim2.fromScale(1, 0.45),
				layoutOrder = 1,
				props = { TextColor3 = (theme.rarity :: any)[row.rarity] },
			}),
			Hint = if selected
				then e(Text, {
					text = `[{props.pickupKey}] Pick up`,
					role = "MutedText",
					size = UDim2.fromScale(1, 0.3),
					layoutOrder = 2,
				})
				else nil,
		}),

		-- One hit target over the whole row, above Slot's own button, so hovering anywhere on the row
		-- selects it and a click anywhere picks it up. Slot's button would otherwise claim the icon.
		Hit = e("TextButton", {
			Text = "",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 50,
			[React.Event.MouseEnter] = function()
				props.onHovered(row.uid)
			end,
			[React.Event.Activated] = function()
				props.onActivated(row.uid)
			end,
		}),
	})
end

return LootRow
