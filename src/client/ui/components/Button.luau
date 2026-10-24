--!strict
-- Action button: a frame of light with display type. "primary" is filled with the accent and dark
-- type; "secondary" is outline only and fills faintly on hover.
--
-- Hover is component state driving a spring, so the response is the same snap everywhere and a
-- skin's motion preset changes every button at once.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ThemeContext = require(script.Parent.Parent.hooks.ThemeContext)
local useSpring = require(script.Parent.Parent.hooks.useSpring)

export type Props = {
	text: string,
	onActivated: (() -> ())?,
	enabled: boolean?,
	variant: ("primary" | "secondary")?,
	size: UDim2?,
	layoutOrder: number?,
	fill: boolean?,
	-- Caps the scaled text, so a tall button does not get billboard-sized lettering.
	maxTextSize: number?,
}

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function Button(props: Props)
	local theme = ThemeContext.useTheme()
	local hovered, setHovered = React.useState(false)
	local enabled = props.enabled ~= false
	local primary = (props.variant or "primary") == "primary"
	local glow = useSpring(if hovered and enabled then 1 else 0, theme.motion.snap)

	local children: { [string]: any } = {
		Outline = React.createElement("UIStroke", {
			Color = if enabled then theme.color.stroke else theme.color.textDisabled,
			Thickness = theme.metrics.strokeThin,
			Transparency = if enabled then 0 else 0.5,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		Padding = React.createElement("UIPadding", {
			PaddingLeft = UDim.new(0, theme.metrics.paddingSm),
			PaddingRight = UDim.new(0, theme.metrics.paddingSm),
			PaddingTop = UDim.new(0.18, 0),
			PaddingBottom = UDim.new(0.18, 0),
		}),
		TextCap = React.createElement("UITextSizeConstraint", {
			MaxTextSize = props.maxTextSize or 28,
		}),
		Scale = React.createElement("UIScale", {
			Scale = glow:map(function(v: number)
				return 1 + 0.04 * v
			end),
		}),
	}
	if props.fill then
		children.Flex = React.createElement("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill })
	end

	return React.createElement("TextButton", {
		Text = string.upper(props.text),
		Size = props.size or UDim2.new(0, 96, 1, 0),
		LayoutOrder = props.layoutOrder,
		BackgroundColor3 = theme.color.accent,
		BackgroundTransparency = if not enabled
			then 1
			elseif primary then glow:map(function(v: number)
				return lerp(0.08, 0, v)
			end)
			else glow:map(function(v: number)
				return lerp(1, 0.82, v)
			end),
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Active = enabled,
		FontFace = theme.face.display,
		TextScaled = true,
		TextColor3 = if not enabled
			then theme.color.textDisabled
			elseif primary then theme.color.textOnAccent
			else theme.color.textPrimary,

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
