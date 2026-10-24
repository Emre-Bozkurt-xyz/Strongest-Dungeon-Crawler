--!strict
-- A panel's title: a lit marker, the title, and a line of light beneath it fading away from the text.
--
-- The underline spans the header rather than starting where the title ends: the title is scaled to
-- the header's height, so its width is not known without measuring, and an underline that fades out
-- reads the same either way.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ThemeContext = require(script.Parent.Parent.hooks.ThemeContext)
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
	-- Left (default) puts the marker before the title and fades the line rightward; Center fades it
	-- out both ways from the middle.
	alignX: Enum.TextXAlignment?,
	-- Overrides the heading colour, e.g. to tint an item name by rarity.
	color: Color3?,
}

local function Header(props: Props)
	local theme = ThemeContext.useTheme()
	local centred = props.alignX == Enum.TextXAlignment.Center

	-- Marker and title share a row, the marker square to the header's height and the title filling
	-- what is left, so the gap between them holds at any header width.
	local row: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		TitleCell = e("Frame", {
			Size = UDim2.fromScale(0, 1),
			BackgroundTransparency = 1,
			LayoutOrder = 2,
		}, {
			Flex = e("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }),
			Title = e(Text, {
				text = props.title,
				role = "PanelHeading",
				size = UDim2.fromScale(1, 0.68),
				position = UDim2.fromScale(0, 0.5),
				anchorPoint = Vector2.new(0, 0.5),
				alignX = props.alignX or Enum.TextXAlignment.Left,
				props = if props.color then { TextColor3 = props.color } else nil,
			}),
		}),
	}
	if not centred then
		row.MarkerCell = e("Frame", {
			Size = UDim2.fromScale(0.75, 1),
			SizeConstraint = Enum.SizeConstraint.RelativeYY,
			BackgroundTransparency = 1,
			LayoutOrder = 1,
		}, {
			Marker = e("Frame", {
				Size = UDim2.fromScale(0.28, 0.28),
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromScale(0.05, 0.5),
				Rotation = 45,
				BackgroundColor3 = props.color or theme.color.stroke,
				BorderSizePixel = 0,
			}),
		})
	end

	return e("Frame", {
		LayoutOrder = props.layoutOrder,
		Size = UDim2.fromScale(props.width or 1, props.height or 0.09),
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		BackgroundTransparency = 1,
	}, {
		Row = e("Frame", {
			Size = UDim2.fromScale(1, 0.9),
			BackgroundTransparency = 1,
		}, row),
		Underline = e("Frame", {
			Size = UDim2.new(1, 0, 0, 1),
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			BackgroundColor3 = props.color or theme.color.stroke,
			BorderSizePixel = 0,
		}, {
			Fade = e("UIGradient", {
				Transparency = if centred
					then NumberSequence.new({
						NumberSequenceKeypoint.new(0, 1),
						NumberSequenceKeypoint.new(0.5, 0.1),
						NumberSequenceKeypoint.new(1, 1),
					})
					else NumberSequence.new({
						NumberSequenceKeypoint.new(0, 0.1),
						NumberSequenceKeypoint.new(1, 1),
					}),
			}),
		}),
	})
end

return Header
