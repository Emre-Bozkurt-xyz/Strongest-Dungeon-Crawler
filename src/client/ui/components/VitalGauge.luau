--!strict
-- One vital: icon and caption in a column at the left, fill bar to their right, current/max readout
-- beneath it.
--
-- Shared because SystemPanel and StatusPreviewPanel had grown near-identical private copies of this
-- composition, and the icon/caption alignment bug existed in both -- they were separate absolutely
-- positioned boxes of different widths with different alignments, so nothing lined them up. Here
-- they share one column and both centre within it.
--
-- The fill eases; the readout text snaps. That split is deliberate and matches the Studio
-- controllers, which tweened FillPanel.Size but wrote the label text directly -- a smoothly sliding
-- number is harder to read than one that changes once.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local Gauge = require(script.Parent.Gauge)
local Text = require(script.Parent.Text)
local ThemeContext = require(script.Parent.Parent.hooks.ThemeContext)
local useTweenedNumber = require(script.Parent.Parent.hooks.useTweenedNumber)

local e = React.createElement

export type Vital = {
	current: number,
	max: number,
	ratio: number,
}

export type Props = {
	icon: string,
	caption: string,
	vital: Vital,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	-- Width of the icon/caption column, as a fraction of the whole row.
	columnWidth: number?,
}

-- The caption is deliberately much shorter than the icon rather than matching it: both are scaled to
-- fill their boxes, so equal heights make a three-letter label read as larger than the glyph above
-- it.
local ICON_HEIGHT = 0.46
local CAPTION_HEIGHT = 0.26

local function VitalGauge(props: Props)
	local theme = ThemeContext.useTheme()
	local ratio = useTweenedNumber(props.vital.ratio)

	local column = props.columnWidth or 0.16
	local barLeft = column + 0.04

	return e("Frame", {
		Size = props.size or UDim2.fromScale(1, 1),
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		LayoutOrder = props.layoutOrder,
		BackgroundTransparency = 1,
	}, {
		-- One column owning both, so they cannot drift apart.
		Legend = e("Frame", {
			Size = UDim2.fromScale(column, 1),
			BackgroundTransparency = 1,
		}, {
			Icon = e("ImageLabel", {
				Image = props.icon,
				Size = UDim2.fromScale(1, ICON_HEIGHT),
				Position = UDim2.fromScale(0.5, 0.04),
				AnchorPoint = Vector2.new(0.5, 0),
				BackgroundTransparency = 1,
				ImageColor3 = theme.color.gaugeTrack,
				ScaleType = Enum.ScaleType.Fit,
			}),
			Caption = e(Text, {
				text = props.caption,
				role = "MutedText",
				size = UDim2.fromScale(1, CAPTION_HEIGHT),
				position = UDim2.fromScale(0.5, 0.56),
				anchorPoint = Vector2.new(0.5, 0),
				alignX = Enum.TextXAlignment.Center,
			}),
		}),

		Bar = e(Gauge, {
			value = ratio,
			size = UDim2.new(1 - barLeft, 0, 0.18, 0),
			position = UDim2.fromScale(barLeft, 0.38),
			anchorPoint = Vector2.new(0, 0.5),
		}),

		Readout = e("Frame", {
			Size = UDim2.new(1 - barLeft, 0, 0.36, 0),
			Position = UDim2.fromScale(1, 0.98),
			AnchorPoint = Vector2.new(1, 1),
			BackgroundTransparency = 1,
		}, {
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Right,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
			Current = e("TextLabel", {
				LayoutOrder = 1,
				Text = tostring(math.floor(props.vital.current)),
				Size = UDim2.fromScale(0, 1),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundTransparency = 1,
				Font = theme.font.body,
				TextColor3 = theme.color.textHeading,
				TextScaled = true,
			}),
			Max = e("TextLabel", {
				LayoutOrder = 2,
				Text = `/{math.floor(props.vital.max)}`,
				Size = UDim2.fromScale(0, 0.72),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundTransparency = 1,
				Font = theme.font.body,
				TextColor3 = theme.color.textMuted,
				TextScaled = true,
			}),
		}),
	})
end

return VitalGauge
