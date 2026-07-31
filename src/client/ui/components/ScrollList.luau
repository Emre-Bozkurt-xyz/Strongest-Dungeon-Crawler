--!strict
-- Vertical auto-sizing list. Wraps the UIListLayout + AutomaticCanvasSize boilerplate that every
-- stacked section would otherwise repeat.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ThemeContext = require(script.Parent.Parent.hooks.ThemeContext)

export type Props = {
	size: UDim2?,
	position: UDim2?,
	layoutOrder: number?,
	gap: number?,
	padding: number?,
	corner: boolean?,
	stroke: boolean?,
	-- Grow to fill the remaining space in a parent UIListLayout.
	fill: boolean?,
	children: any?,
}

local function ScrollList(props: Props)
	local theme = ThemeContext.useTheme()
	local gap = props.gap or theme.metrics.paddingSm

	local children: { [string]: any } = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, gap),
		}),
	}
	if props.corner ~= false then
		children.Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(0, theme.metrics.radiusPanel),
		})
	end
	if props.stroke then
		children.Stroke = React.createElement("UIStroke", {
			Color = theme.color.stroke,
			Thickness = theme.metrics.strokePanel,
			Transparency = 0.5,
		})
	end
	if props.fill then
		children.Flex = React.createElement("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill })
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
	if props.children then
		for key, child in pairs(props.children) do
			children[key] = child
		end
	end

	return React.createElement("ScrollingFrame", {
		Size = props.size or UDim2.fromScale(1, 1),
		Position = props.position,
		LayoutOrder = props.layoutOrder,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = theme.color.stroke,
		ScrollBarImageTransparency = 0.4,
	}, children)
end

return ScrollList
