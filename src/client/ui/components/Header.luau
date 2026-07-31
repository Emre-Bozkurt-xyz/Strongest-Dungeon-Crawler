--!strict
-- A panel's title block: bordered bar with a glowing centred title.
--
-- Mirrors the Header/NameContainer block the Studio panels share -- heavy translucent outline, title
-- in the heading colour with a faint blue stroke on the glyphs.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ThemeContext = require(script.Parent.Parent.hooks.ThemeContext)
local Panel = require(script.Parent.Panel)
local Text = require(script.Parent.Text)

local e = React.createElement

export type Props = {
	title: string,
	layoutOrder: number?,
	-- Scale height within the panel stack.
	height: number?,
	width: number?,
	-- For panels laid out in "free" mode, where the header is placed rather than stacked.
	position: UDim2?,
	anchorPoint: Vector2?,
	alignX: Enum.TextXAlignment?,
	-- Overrides the heading colour, e.g. to tint an item name by rarity.
	color: Color3?,
}

local function Header(props: Props)
	local theme = ThemeContext.useTheme()

	return e(Panel, {
		stroke = true,
		layoutOrder = props.layoutOrder,
		size = UDim2.new(props.width or 1, 0, props.height or 0.09, 0),
		position = props.position,
		anchorPoint = props.anchorPoint,
		padding = theme.metrics.paddingSm,
		props = { BackgroundTransparency = 1 },
	}, {
		Title = e(Text, {
			text = props.title,
			role = "PanelHeading",
			size = UDim2.fromScale(1, 1),
			alignX = props.alignX or Enum.TextXAlignment.Center,
			glow = true,
			props = if props.color then { TextColor3 = props.color } else nil,
		}),
	})
end

return Header
