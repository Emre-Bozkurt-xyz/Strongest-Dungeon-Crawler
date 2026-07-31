--!strict
-- Scrolling fixed-cell grid. The container for slots.
--
-- Cells are square by default because slots are; `cell` is in canvas pixels, not scale, so a slot is
-- the same size whether the grid holds four items or forty.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ThemeContext = require(script.Parent.Parent.hooks.ThemeContext)

local e = React.createElement

export type Props = {
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	cell: number?,
	gap: number?,
	padding: number?,
	align: Enum.HorizontalAlignment?,
	stroke: boolean?,
	corner: boolean?,
	-- Grow to fill the remaining space in a parent UIListLayout.
	fill: boolean?,
	children: any?,
}

local function Grid(props: Props)
	local theme = ThemeContext.useTheme()
	local cell = props.cell or 96
	local gap = props.gap or theme.metrics.paddingMd

	local children: { [string]: any } = {
		-- Left-aligned, not centred: the contents are a growing list, so a partial last row would
		-- otherwise float in the middle and the whole grid would shift sideways as items are added
		-- or a filter narrows it.
		Layout = e("UIGridLayout", {
			CellSize = UDim2.fromOffset(cell, cell),
			CellPadding = UDim2.fromOffset(gap, gap),
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = props.align or Enum.HorizontalAlignment.Left,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	if props.corner ~= false then
		children.Corner = e("UICorner", { CornerRadius = UDim.new(0, theme.metrics.radiusPanel) })
	end
	if props.stroke then
		children.Stroke = e("UIStroke", {
			Color = theme.color.stroke,
			Thickness = theme.metrics.strokePanel,
			Transparency = 0.5,
		})
	end
	if props.fill then
		children.Flex = e("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill })
	end
	if props.padding then
		local pad = UDim.new(0, props.padding)
		children.Padding = e("UIPadding", {
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

	return e("ScrollingFrame", {
		Size = props.size or UDim2.fromScale(1, 1),
		Position = props.position,
		AnchorPoint = props.anchorPoint,
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

return Grid
