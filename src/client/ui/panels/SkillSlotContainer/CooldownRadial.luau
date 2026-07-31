--!strict
-- The cooldown "cutout" ring on a skill slot: a thin animated border sweeping around the icon to show
-- how much cooldown remains, rather than a wedge covering the whole icon.
--
-- Ported from CooldownRadial in docs/ui/SkillSlotContainer.rbxmx. It uses the same two-half masking
-- trick as components/RadialGauge (rotate the UIGradient, never the Frame -- ClipsDescendants does
-- not clip a rotated descendant) but square rather than circular, and its punched-out centre repaints
-- the button's OWN live background/transparency instead of a fixed panel colour -- that is what makes
-- it read as a border cut into the icon rather than a ring floating in front of a card.
--
-- Not merged into RadialGauge: the shapes differ (square vs. circular) and the centre-fill needs the
-- caller's live background rather than a fixed one, so sharing would mean branching RadialGauge for a
-- case only this panel needs, and RadialGauge already serves StatusPreviewPanel. This is the second
-- use of the masking trick, though, so a third use should promote a shared primitive instead of a
-- third copy.
--
-- `value` is 1 at the moment a cooldown starts (fully covered) and falls to 0 at ready -- the inverse
-- of RadialGauge's "how full" sense, matching SkillPacer's cooldown-remaining convention.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ThemeContext = require(script.Parent.Parent.Parent.hooks.ThemeContext)

local e = React.createElement

export type Props = {
	-- 0..1, or a binding producing it.
	value: any,
	visible: any,
	baseColor: Color3,
	baseTransparency: number,
}

-- Half-mask: opaque up to the midpoint, invisible after it. The 0.001 gap between the two middle
-- keypoints is what makes the edge hard rather than a fade.
local function halfMaskGradient(color: Color3, rotation: any)
	return e("UIGradient", {
		Color = ColorSequence.new(color),
		Rotation = rotation,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.5, 0),
			NumberSequenceKeypoint.new(0.501, 1),
			NumberSequenceKeypoint.new(1, 1),
		}),
	})
end

-- Absolute sweep angle, clamped to the half this gradient is responsible for.
local function sweep(value: any, from: number, to: number): any
	local function resolve(v: number): number
		return math.clamp(math.clamp(v, 0, 1) * 360, from, to)
	end
	if type(value) == "number" then
		return resolve(value)
	end
	return (value :: any):map(resolve)
end

local function CooldownRadial(props: Props)
	local theme = ThemeContext.useTheme()
	local tint = theme.color.cooldownRadialTint

	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		Visible = props.visible,
		BackgroundTransparency = 1,
		ZIndex = 2,
	}, {
		Left = e("Frame", {
			Size = UDim2.fromScale(0.5, 1),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = 2,
		}, {
			Circle = e("Frame", {
				Size = UDim2.fromScale(2, 1),
				BackgroundColor3 = tint,
				BackgroundTransparency = 0.45,
				BorderSizePixel = 0,
			}, {
				Gradient = halfMaskGradient(tint, sweep(props.value, 180, 360)),
			}),
		}),

		Right = e("Frame", {
			Size = UDim2.fromScale(0.5, 1),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = 2,
		}, {
			Circle = e("Frame", {
				Size = UDim2.fromScale(2, 1),
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromScale(1, 0),
				BackgroundColor3 = tint,
				BackgroundTransparency = 0.45,
				BorderSizePixel = 0,
			}, {
				Gradient = halfMaskGradient(tint, sweep(props.value, 0, 180)),
			}),
		}),

		-- Punches the centre back out to the button's own look, leaving only the outer band swept by
		-- Left/Right visible -- the "cutout" the export's name refers to.
		CenterCutout = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 3,
		}, {
			Padding = e("UIPadding", {
				PaddingTop = UDim.new(0, 4),
				PaddingBottom = UDim.new(0, 4),
				PaddingLeft = UDim.new(0, 4),
				PaddingRight = UDim.new(0, 4),
			}),
			Fill = e("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundColor3 = props.baseColor,
				BackgroundTransparency = props.baseTransparency,
				BorderSizePixel = 0,
			}),
		}),
	})
end

return CooldownRadial
