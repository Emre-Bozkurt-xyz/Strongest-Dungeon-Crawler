--!strict
-- Corner brackets: four L-shaped corners joined by a faint hairline. The System's frame shape -- it
-- reads as a projected window rather than a bordered box, and the corners are what move when a window
-- materialises.
--
-- Chrome, so it fills its parent and must not sit under that parent's UIPadding: padding applies to
-- every child and would push the corners onto the content they frame. PanelFrame keeps content in a
-- separate padded body for that reason.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ThemeContext = require(script.Parent.Parent.hooks.ThemeContext)

local e = React.createElement

export type Props = {
	-- Which bracket spec from the theme's chrome: a whole panel, or something small (a card, a slot).
	size: ("panel" | "small")?,
	color: Color3?,
	-- 0..1 binding. Slides the corners from the centre out to their places and fades the hairline in
	-- once they are nearly there. Omit for static brackets.
	progress: any?,
	-- Overrides the theme's hairline transparency; 1 hides it, leaving only corners.
	edgeTransparency: number?,
	zIndex: number?,
}

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function Brackets(props: Props)
	local theme = ThemeContext.useTheme()
	local spec = if props.size == "small" then theme.chrome.bracket else theme.chrome.panelBracket
	local color = props.color or theme.color.stroke
	local edge = props.edgeTransparency or theme.chrome.edgeTransparency
	local z = props.zIndex or 20

	local children: { [string]: any } = {}
	for _, corner in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
		local cx, cy = corner[1], corner[2]
		children[`Corner{cx}{cy}`] = e("Frame", {
			Size = UDim2.fromOffset(spec.length, spec.length),
			AnchorPoint = Vector2.new(cx, cy),
			Position = if props.progress
				then props.progress:map(function(p: number)
					return UDim2.fromScale(lerp(0.5, cx, p), lerp(0.5, cy, p))
				end)
				else UDim2.fromScale(cx, cy),
			BackgroundTransparency = 1,
			ZIndex = z,
		}, {
			Horizontal = e("Frame", {
				Size = UDim2.new(1, 0, 0, spec.thickness),
				AnchorPoint = Vector2.new(cx, cy),
				Position = UDim2.fromScale(cx, cy),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
				ZIndex = z,
			}),
			Vertical = e("Frame", {
				Size = UDim2.new(0, spec.thickness, 1, 0),
				AnchorPoint = Vector2.new(cx, cy),
				Position = UDim2.fromScale(cx, cy),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
				ZIndex = z,
			}),
		})
	end
	children.Edge = e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = z - 1,
	}, {
		Stroke = e("UIStroke", {
			Color = color,
			Thickness = 1,
			Transparency = if props.progress
				then props.progress:map(function(p: number)
					return lerp(1, edge, math.clamp((p - 0.6) / 0.4, 0, 1))
				end)
				else edge,
		}),
	})

	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = z,
	}, children)
end

return Brackets
