--!strict
-- A filled bar: health, mana, stamina, cast progress.
--
-- Ported from the ProgressBar blocks in docs/ui/StatusPreviewPanel.rbxmx -- outlined track, 1px
-- inset, rounded fill.
--
-- `value` accepts a React binding as well as a number. Anything driven per-frame (a cast bar, a
-- draining stamina meter) should pass a binding so it animates without re-rendering the tree; a
-- plain number is fine for values that change on a server update.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ThemeContext = require(script.Parent.Parent.hooks.ThemeContext)

local e = React.createElement

export type Props = {
	-- 0..1, or a binding producing it.
	value: any,
	color: Color3?,
	strokeThickness: number?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
}

local function Gauge(props: Props)
	local theme = ThemeContext.useTheme()

	local fillSize = if type(props.value) == "number"
		then UDim2.fromScale(math.clamp(props.value, 0, 1), 1)
		else (props.value :: any):map(function(v: number)
			return UDim2.fromScale(math.clamp(v, 0, 1), 1)
		end)

	return e("Frame", {
		Size = props.size or UDim2.new(1, 0, 0, 12),
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		LayoutOrder = props.layoutOrder,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Stroke = e("UIStroke", {
			Color = theme.color.gaugeTrack,
			Thickness = props.strokeThickness or theme.metrics.strokeThin,
			Transparency = 0,
		}),
		Padding = e("UIPadding", {
			PaddingTop = UDim.new(0, 1),
			PaddingBottom = UDim.new(0, 1),
			PaddingLeft = UDim.new(0, 1),
			PaddingRight = UDim.new(0, 1),
		}),
		Fill = e("Frame", {
			Size = fillSize,
			BackgroundColor3 = props.color or theme.color.gaugeFill,
			BorderSizePixel = 0,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
		}),
	})
end

return Gauge
