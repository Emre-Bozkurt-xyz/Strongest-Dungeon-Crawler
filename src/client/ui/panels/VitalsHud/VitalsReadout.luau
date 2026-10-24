--!strict
-- HP and MP as captioned bars with the current value, and stamina as a bare hairline beneath them.
--
-- Built for a glance in the middle of a fight: the bars are what gets read, so they carry the colour
-- and the numbers stay small. HP leaves a trail where it was, so a hit shows how much it took even
-- after the bar has already dropped.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local Brackets = require(script.Parent.Parent.Parent.components.Brackets)
local ThemeContext = require(script.Parent.Parent.Parent.hooks.ThemeContext)
local useSpring = require(script.Parent.Parent.Parent.hooks.useSpring)
local Selector = require(script.Parent.Parent.Parent.selectors.systemStatus)

local e = React.createElement

export type Props = {
	health: Selector.VitalView?,
	mana: Selector.VitalView?,
	stamina: Selector.VitalView?,
}

-- Screen pixels. The container sizes and places the readout from SIZE, so the layout below has to
-- add up to it.
local PAD_X, PAD_Y = 10, 8
local CAPTION_WIDTH = 26
local VALUE_WIDTH = 36
local ROW_HEIGHT = 14
local STAMINA_HEIGHT = 3
local GAP = 5

local VitalsReadout = {}

VitalsReadout.SIZE = Vector2.new(210, PAD_Y * 2 + ROW_HEIGHT * 2 + STAMINA_HEIGHT + GAP * 2)

local function Bar(props: {
	ratio: number,
	color: Color3,
	thickness: number,
	trail: boolean?,
	size: UDim2,
	position: UDim2?,
	anchorPoint: Vector2?,
})
	local theme = ThemeContext.useTheme()
	local fill = useSpring(props.ratio, theme.motion.snap)
	-- Always called so the hook order is fixed; only drawn when asked for.
	local trail = useSpring(props.ratio, theme.motion.drift)

	local function width(v: number): UDim2
		return UDim2.fromScale(math.clamp(v, 0, 1), 1)
	end

	return e("Frame", {
		Size = props.size,
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		BackgroundTransparency = 1,
	}, {
		Track = e("Frame", {
			Size = UDim2.new(1, 0, 0, props.thickness),
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			BackgroundColor3 = theme.color.gaugeTrack,
			BackgroundTransparency = 0.2,
			BorderSizePixel = 0,
		}, {
			Trail = if props.trail
				then e("Frame", {
					Size = trail:map(width),
					BackgroundColor3 = theme.color.textPrimary,
					BackgroundTransparency = 0.25,
					BorderSizePixel = 0,
				})
				else nil,
			Fill = e("Frame", {
				Size = fill:map(width),
				BackgroundColor3 = props.color,
				BorderSizePixel = 0,
				ZIndex = 2,
			}),
		}),
	})
end

local function Row(props: {
	caption: string,
	vital: Selector.VitalView,
	color: Color3,
	thickness: number,
	trail: boolean?,
	layoutOrder: number,
})
	local theme = ThemeContext.useTheme()
	local barWidth = -(CAPTION_WIDTH + VALUE_WIDTH)

	return e("Frame", {
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		LayoutOrder = props.layoutOrder,
		BackgroundTransparency = 1,
	}, {
		Caption = e("TextLabel", {
			Text = props.caption,
			Size = UDim2.new(0, CAPTION_WIDTH, 1, 0),
			BackgroundTransparency = 1,
			FontFace = theme.face.display,
			TextSize = theme.type.label,
			TextColor3 = theme.color.textMuted,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Bar = e(Bar, {
			ratio = props.vital.ratio,
			color = props.color,
			thickness = props.thickness,
			trail = props.trail,
			size = UDim2.new(1, barWidth, 1, 0),
			position = UDim2.fromOffset(CAPTION_WIDTH, 0),
		}),
		Value = e("TextLabel", {
			Text = tostring(math.floor(props.vital.current)),
			Size = UDim2.new(0, VALUE_WIDTH, 1, 0),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			BackgroundTransparency = 1,
			FontFace = theme.face.mono,
			TextSize = theme.type.label,
			TextColor3 = theme.color.textPrimary,
			TextXAlignment = Enum.TextXAlignment.Right,
		}),
	})
end

function VitalsReadout.render(props: Props)
	local theme = ThemeContext.useTheme()

	local rows: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, GAP),
		}),
		Padding = e("UIPadding", {
			PaddingLeft = UDim.new(0, PAD_X),
			PaddingRight = UDim.new(0, PAD_X),
			PaddingTop = UDim.new(0, PAD_Y),
			PaddingBottom = UDim.new(0, PAD_Y),
		}),
	}
	if props.health then
		rows.Health = e(Row, {
			caption = "HP",
			vital = props.health,
			color = theme.color.vitalHealth,
			thickness = 5,
			trail = true,
			layoutOrder = 1,
		})
	end
	if props.mana then
		rows.Mana = e(Row, {
			caption = "MP",
			vital = props.mana,
			color = theme.color.vitalMana,
			thickness = 3,
			layoutOrder = 2,
		})
	end
	if props.stamina then
		-- Uncaptioned and lined up under the other bars: it changes constantly while moving, so it
		-- should be noticed when it runs low rather than read.
		rows.Stamina = e("Frame", {
			Size = UDim2.new(1, 0, 0, STAMINA_HEIGHT),
			LayoutOrder = 3,
			BackgroundTransparency = 1,
		}, {
			Bar = e(Bar, {
				ratio = props.stamina.ratio,
				color = theme.color.vitalStamina,
				thickness = STAMINA_HEIGHT - 1,
				size = UDim2.new(1, -(CAPTION_WIDTH + VALUE_WIDTH), 1, 0),
				position = UDim2.fromOffset(CAPTION_WIDTH, 0),
			}),
		})
	end

	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		-- Enough fill to stay legible over a bright sky or a spell. Corners only, no outline: over
		-- gameplay a full frame reads as a box in the way.
		Fill = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = theme.color.surface,
			BackgroundTransparency = 0.4,
			BorderSizePixel = 0,
		}),
		Brackets = e(Brackets, { size = "small", edgeTransparency = 1 }),
		Body = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 2,
		}, rows),
	})
end

return VitalsReadout
