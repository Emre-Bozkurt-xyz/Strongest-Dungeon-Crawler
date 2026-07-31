--!strict
-- Themed surface container with optional corner, stroke and gradient.
--
-- `role` selects the surface treatment: "PanelBackdrop" for the outer wash, "PanelSurface" for the
-- panel body over it, "PanelBlock" for a bordered block inside a panel, "AmbientPanel" for
-- always-on gameplay surfaces that must stay legible against the world (R7).
--
-- Stroke defaults to the design's heavy half-transparent outline rather than a hairline. That
-- outline is what separates the blocks in this design -- a 1px opaque border reads as a completely
-- different UI.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ThemeContext = require(script.Parent.Parent.hooks.ThemeContext)
local Themes = require(ReplicatedStorage.Shared.ui.themes)

export type GradientSpec = {
	rotation: number?,
	from: number?,
	to: number?,
}

export type Props = {
	role: Themes.StyleRole?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	padding: number?,
	corner: boolean?,
	stroke: boolean?,
	strokeThickness: number?,
	strokeTransparency: number?,
	-- Vertical translucency ramp. The Studio panel used this to fade its body downward.
	gradient: GradientSpec?,
	-- Grow to fill the remaining space in a parent UIListLayout.
	fill: boolean?,
	clips: boolean?,
	props: { [string]: any }?,
	children: any?,
}

local function Panel(props: Props)
	local theme = ThemeContext.useTheme()
	local styled = ThemeContext.useStyle(props.role or "PanelSurface", props.props)

	local merged: { [string]: any } = table.clone(styled)
	merged.Size = props.size or UDim2.fromScale(1, 1)
	merged.Position = props.position
	merged.AnchorPoint = props.anchorPoint
	merged.LayoutOrder = props.layoutOrder
	if props.clips then
		merged.ClipsDescendants = true
	end

	local children: { [string]: any } = {}
	if props.corner ~= false then
		children.Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(0, theme.metrics.radiusPanel),
		})
	end
	if props.stroke then
		children.Stroke = React.createElement("UIStroke", {
			Color = theme.color.stroke,
			Thickness = props.strokeThickness or theme.metrics.strokePanel,
			Transparency = props.strokeTransparency or 0.5,
		})
	end
	if props.gradient then
		local spec = props.gradient
		children.Gradient = React.createElement("UIGradient", {
			Rotation = spec.rotation or -97,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, spec.from or 0.1125),
				NumberSequenceKeypoint.new(1, spec.to or 0.5625),
			}),
		})
	end
	if props.fill then
		children.Flex = React.createElement("UIFlexItem", {
			FlexMode = Enum.UIFlexMode.Fill,
		})
	end
	if props.padding then
		local pad = UDim.new(0, props.padding)
		children.Padding = React.createElement("UIPadding", {
			PaddingTop = pad,
			PaddingBottom = pad,
			PaddingLeft = pad,
			PaddingRight = pad,
		})
	end
	-- Children are merged in, not nested under a single key. Nesting a dict inside a child slot
	-- makes the reconciler flatten a table that is not an element, which is what produced
	-- "createTextInstance is unimplemented".
	if props.children then
		for key, child in pairs(props.children) do
			children[key] = child
		end
	end

	return React.createElement("Frame", merged, children)
end

return Panel
