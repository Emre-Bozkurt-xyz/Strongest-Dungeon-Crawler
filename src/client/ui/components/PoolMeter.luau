--!strict
-- One pool at panel size: icon and caption on the left, current/max on the right, and a continuous
-- bar beneath spanning the row, with faint tenth marks so its level reads at a glance.
--
-- The segmented gauge is the HUD's: at panel size its cells read as a barcode. This is the same
-- information drawn for a bigger, calmer surface. The fill springs to its value and a grey trail follows
-- on a slower spring, so a hit shows how much it took.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ThemeContext = require(script.Parent.Parent.hooks.ThemeContext)
local useSpring = require(script.Parent.Parent.hooks.useSpring)

local e = React.createElement

export type Props = {
	icon: string?,
	caption: string,
	current: number,
	max: number,
	color: Color3,
	layoutOrder: number?,
	size: UDim2?,
}

-- Pixels.
local LABEL_HEIGHT = 20
local BAR_HEIGHT = 6
local GAP = 6

local PoolMeter = {}

PoolMeter.HEIGHT = LABEL_HEIGHT + GAP + BAR_HEIGHT

local function width(v: number): UDim2
	return UDim2.fromScale(math.clamp(v, 0, 1), 1)
end

function PoolMeter.render(props: Props)
	local theme = ThemeContext.useTheme()
	local ratio = if props.max > 0 then math.clamp(props.current / props.max, 0, 1) else 0
	local fill = useSpring(ratio, theme.motion.snap)
	local trail = useSpring(ratio, theme.motion.drift)

	local ticks: { [string]: any } = {}
	for index = 1, 9 do
		ticks[`Tick{index}`] = e("Frame", {
			Size = UDim2.new(0, 1, 1, 0),
			Position = UDim2.fromScale(index / 10, 0),
			BackgroundColor3 = theme.color.surface,
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
			ZIndex = 4,
		})
	end

	return e("Frame", {
		Size = props.size or UDim2.new(1, 0, 0, PoolMeter.HEIGHT),
		LayoutOrder = props.layoutOrder,
		BackgroundTransparency = 1,
	}, {
		Caption = e("Frame", {
			Size = UDim2.new(0.5, 0, 0, LABEL_HEIGHT),
			BackgroundTransparency = 1,
		}, {
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 8),
			}),
			-- The slot is kept even without an icon, so captions line up down a stack of meters.
			Icon = e("ImageLabel", {
				Image = props.icon or "",
				Size = UDim2.fromOffset(14, 14),
				LayoutOrder = 1,
				BackgroundTransparency = 1,
				ImageColor3 = theme.color.textMuted,
				ScaleType = Enum.ScaleType.Fit,
			}),
			Label = e("TextLabel", {
				Text = props.caption,
				Size = UDim2.fromScale(0, 1),
				AutomaticSize = Enum.AutomaticSize.X,
				LayoutOrder = 2,
				BackgroundTransparency = 1,
				FontFace = theme.face.display,
				TextSize = theme.type.label,
				TextColor3 = theme.color.textMuted,
			}),
		}),
		Value = e("TextLabel", {
			Text = `{math.floor(props.current)}<font size="{theme.type.small}" color="#{theme.color.textMuted:ToHex()}"> / {math.floor(
				props.max
			)}</font>`,
			RichText = true,
			Size = UDim2.new(0.5, 0, 0, LABEL_HEIGHT),
			Position = UDim2.fromScale(0.5, 0),
			BackgroundTransparency = 1,
			FontFace = theme.face.mono,
			TextSize = theme.type.title,
			TextColor3 = theme.color.textHeading,
			TextXAlignment = Enum.TextXAlignment.Right,
		}),
		Bar = e("Frame", {
			Size = UDim2.new(1, 0, 0, BAR_HEIGHT),
			Position = UDim2.fromOffset(0, LABEL_HEIGHT + GAP),
			BackgroundColor3 = theme.color.gaugeTrack,
			BackgroundTransparency = 0.1,
			BorderSizePixel = 0,
		}, {
			Trail = e("Frame", {
				Size = trail:map(width),
				BackgroundColor3 = theme.color.textMuted,
				BackgroundTransparency = 0.35,
				BorderSizePixel = 0,
				ZIndex = 2,
			}),
			Fill = e("Frame", {
				Size = fill:map(width),
				BackgroundColor3 = props.color,
				BorderSizePixel = 0,
				ZIndex = 3,
			}),
			Ticks = e("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ZIndex = 4,
			}, ticks),
		}),
	})
end

return PoolMeter
