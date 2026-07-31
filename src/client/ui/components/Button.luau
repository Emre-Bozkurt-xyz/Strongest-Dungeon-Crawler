--!strict
-- Themed action button: light gradient fill, dark ink, rounded.
--
-- Hover is component state rather than a stylesheet pseudo-selector, which is the direct
-- replacement for Studio's `:Hover` rules (R2). Hover brightens by dropping the gradient's
-- transparency rather than swapping the fill, so the button keeps its identity while lit.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ThemeContext = require(script.Parent.Parent.hooks.ThemeContext)

export type Props = {
	text: string,
	onActivated: (() -> ())?,
	enabled: boolean?,
	size: UDim2?,
	layoutOrder: number?,
	fill: boolean?,
}

local function Button(props: Props)
	local theme = ThemeContext.useTheme()
	local hovered, setHovered = React.useState(false)
	local enabled = props.enabled ~= false

	local children: { [string]: any } = {
		Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(0, theme.metrics.radiusControl),
		}),
		Padding = React.createElement("UIPadding", {
			PaddingLeft = UDim.new(0, theme.metrics.paddingSm),
			PaddingRight = UDim.new(0, theme.metrics.paddingSm),
			PaddingTop = UDim.new(0, 4),
			PaddingBottom = UDim.new(0, 4),
		}),
		Gradient = React.createElement("UIGradient", {
			Color = ColorSequence.new(theme.color.accentFrom, theme.color.accentTo),
			Rotation = -10,
			Transparency = if enabled and hovered then NumberSequence.new(0) else NumberSequence.new(0.15),
		}),
	}
	if props.fill then
		children.Flex = React.createElement("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill })
	end

	return React.createElement("TextButton", {
		Text = props.text,
		Size = props.size or UDim2.new(0, 96, 1, 0),
		LayoutOrder = props.layoutOrder,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = if enabled then 0 else 0.6,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Active = enabled,
		Font = theme.font.action,
		TextScaled = true,
		TextColor3 = if enabled then theme.color.textOnAccent else theme.color.textDisabled,

		[React.Event.Activated] = if enabled then props.onActivated else nil,
		[React.Event.MouseEnter] = function()
			setHovered(true)
		end,
		[React.Event.MouseLeave] = function()
			setHovered(false)
		end,
	}, children)
end

return Button
