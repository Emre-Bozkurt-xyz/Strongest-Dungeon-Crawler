--!strict
-- HP and MP as rows, stamina as a ring spanning both: the vitals as the HUD strip and the System
-- panel both show them.
--
-- The hand-built status panel's elements -- icon, caption, gauge, current/max per vital and a
-- stamina ring -- drawn slim. The gauges are the style tile's segmented cells, and HP keeps a trail
-- of the cells a hit took. Fills its parent; the parent supplies the chrome and padding.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local RadialGauge = require(script.Parent.RadialGauge)
local SegmentedGauge = require(script.Parent.SegmentedGauge)
local ThemeContext = require(script.Parent.Parent.hooks.ThemeContext)
local useTweenedNumber = require(script.Parent.Parent.hooks.useTweenedNumber)
local Selector = require(script.Parent.Parent.selectors.systemStatus)

local e = React.createElement

export type Props = {
	vitals: { Selector.VitalView },
	size: UDim2?,
	position: UDim2?,
	layoutOrder: number?,
}

local HEART_ICON = "rbxassetid://100398419080154"
local DROPLET_ICON = "rbxassetid://109364647302001"

-- Pixels (logical ones on a logical-width surface).
local ROW_HEIGHT = 16
local ROW_GAP = 6
local ICON_SIZE = 13
local CAPTION_WIDTH = 24
local VALUE_WIDTH = 64
local RING_SIZE = ROW_HEIGHT * 2 + ROW_GAP

local VitalsBlock = {}

-- Height the block needs; a parent sizing it in pixels uses this.
VitalsBlock.HEIGHT = RING_SIZE

local function findVital(vitals: { Selector.VitalView }, label: string): Selector.VitalView?
	for _, vital in ipairs(vitals) do
		if vital.label == label then
			return vital
		end
	end
	return nil
end

local function VitalRow(props: {
	icon: string,
	caption: string,
	vital: Selector.VitalView,
	color: Color3,
	gaugeHeight: number,
	trail: boolean?,
	layoutOrder: number,
})
	local theme = ThemeContext.useTheme()

	return e("Frame", {
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		LayoutOrder = props.layoutOrder,
		BackgroundTransparency = 1,
	}, {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		}),
		Icon = e("ImageLabel", {
			Image = props.icon,
			Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE),
			LayoutOrder = 1,
			BackgroundTransparency = 1,
			ImageColor3 = theme.color.textPrimary,
			ScaleType = Enum.ScaleType.Fit,
		}),
		Caption = e("TextLabel", {
			Text = props.caption,
			Size = UDim2.new(0, CAPTION_WIDTH, 1, 0),
			LayoutOrder = 2,
			BackgroundTransparency = 1,
			FontFace = theme.face.display,
			TextSize = theme.type.label,
			TextColor3 = theme.color.textMuted,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		-- The gauge takes whatever the fixed columns leave, so the panel can be resized freely.
		GaugeCell = e("Frame", {
			Size = UDim2.fromScale(0, 1),
			LayoutOrder = 3,
			BackgroundTransparency = 1,
		}, {
			Flex = e("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }),
			Gauge = e(SegmentedGauge, {
				value = props.vital.ratio,
				color = props.color,
				trail = props.trail,
				size = UDim2.new(1, 0, 0, props.gaugeHeight),
				position = UDim2.fromScale(0, 0.5),
				anchorPoint = Vector2.new(0, 0.5),
			}),
		}),
		-- One label, so current and max sit together however wide the number gets; max is smaller
		-- and dimmer because current is the one being read.
		Value = e("TextLabel", {
			Text = `{math.floor(props.vital.current)}<font size="{theme.type.label - 1}" color="#{theme.color.textMuted:ToHex()}">/{math.floor(
				props.vital.max
			)}</font>`,
			RichText = true,
			Size = UDim2.new(0, VALUE_WIDTH, 1, 0),
			LayoutOrder = 4,
			BackgroundTransparency = 1,
			FontFace = theme.face.mono,
			TextSize = theme.type.small,
			TextColor3 = theme.color.textPrimary,
			TextXAlignment = Enum.TextXAlignment.Right,
		}),
	})
end

function VitalsBlock.render(props: Props)
	local theme = ThemeContext.useTheme()

	local health = findVital(props.vitals, "HP")
	local mana = findVital(props.vitals, "MP")
	local stamina = findVital(props.vitals, "Stamina")
	-- Called unconditionally so the hook order never depends on the stats snapshot's shape.
	local staminaRatio = useTweenedNumber(if stamina then stamina.ratio else 0)

	return e("Frame", {
		Size = props.size or UDim2.fromScale(1, 1),
		Position = props.position,
		LayoutOrder = props.layoutOrder,
		BackgroundTransparency = 1,
	}, {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 12),
		}),
		Rows = e("Frame", {
			Size = UDim2.fromScale(0, 1),
			LayoutOrder = 1,
			BackgroundTransparency = 1,
		}, {
			Flex = e("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }),
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, ROW_GAP),
			}),
			Health = if health
				then e(VitalRow, {
					icon = HEART_ICON,
					caption = "HP",
					vital = health,
					color = theme.color.accent,
					gaugeHeight = 6,
					trail = true,
					layoutOrder = 1,
				})
				else nil,
			Mana = if mana
				then e(VitalRow, {
					icon = DROPLET_ICON,
					caption = "MP",
					vital = mana,
					color = theme.rarity.magic,
					gaugeHeight = 4,
					layoutOrder = 2,
				})
				else nil,
		}),
		Stamina = if stamina
			then e(RadialGauge, {
				value = staminaRatio,
				label = "STA",
				thickness = 0.12,
				textSize = theme.type.label,
				size = UDim2.fromOffset(RING_SIZE, RING_SIZE),
				layoutOrder = 2,
			})
			else nil,
	})
end

return VitalsBlock
