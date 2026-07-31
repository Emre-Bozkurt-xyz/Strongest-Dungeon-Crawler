--!strict
-- A circular fill ring with a label in the middle.
--
-- Roblox has no arc primitive, so this is the standard two-half masking trick, ported from the
-- StaminaBar block in docs/ui/SystemPanel.rbxmx and its driver, StaminaBarController:
--
--   * two clipping containers, each covering one half of the square
--   * inside each, a full-size disc carrying a gradient whose transparency flips hard at the
--     midpoint, so the disc draws exactly a half-disc
--   * rotating *the gradient* sweeps that hard edge around, revealing more of the clipped half
--   * a smaller opaque disc on top punches out the centre, turning the disc into a ring
--
-- Rotation goes on the UIGradient, never on the Frame. `ClipsDescendants` does not clip rotated
-- descendants in Roblox, so rotating the disc instead leaks the whole half-disc past its clip -- it
-- renders as a half-full arc spinning in place rather than an arc that grows.
--
-- The angles are absolute over a full turn: the right half sweeps 0-180 degrees and the left half
-- 180-360, so each is a clamp of the same value rather than two separate ranges.
--
-- `value` accepts a React binding as well as a number, so a per-frame source (stamina draining)
-- animates without re-rendering.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ThemeContext = require(script.Parent.Parent.hooks.ThemeContext)

local e = React.createElement

export type Props = {
	-- 0..1, or a binding producing it.
	value: any,
	label: string?,
	color: Color3?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	-- Fraction of the diameter taken by the punched-out centre.
	thickness: number?,
}

-- Half-disc: opaque up to the midpoint, invisible after it.
local function halfDiscGradient(color: Color3, rotation: any)
	return e("UIGradient", {
		Color = ColorSequence.new(color),
		Rotation = rotation,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.5, 0),
			-- The 0.001 gap is what makes the edge hard rather than a fade.
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

local function RadialGauge(props: Props)
	local theme = ThemeContext.useTheme()
	local color = props.color or theme.color.gaugeFill
	local inner = 1 - (props.thickness or 0.2)

	return e("Frame", {
		Size = props.size or UDim2.fromScale(1, 1),
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		LayoutOrder = props.layoutOrder,
		BackgroundTransparency = 1,
	}, {
		-- Keeps the ring circular whatever the parent does to it.
		Ratio = e("UIAspectRatioConstraint", { AspectRatio = 1 }),

		Track = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = color,
			BackgroundTransparency = 0.9,
			BorderSizePixel = 0,
			ZIndex = 0,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
		}),

		Right = e("Frame", {
			Size = UDim2.fromScale(0.5, 1),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = 1,
		}, {
			Circle = e("Frame", {
				Size = UDim2.fromScale(2, 1),
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromScale(1, 0),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
				Gradient = halfDiscGradient(color, sweep(props.value, 0, 180)),
			}),
		}),

		Left = e("Frame", {
			Size = UDim2.fromScale(0.5, 1),
			BackgroundTransparency = 1,
			ClipsDescendants = true,
			ZIndex = 1,
		}, {
			Circle = e("Frame", {
				Size = UDim2.fromScale(2, 1),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
			}, {
				Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
				Gradient = halfDiscGradient(color, sweep(props.value, 180, 360)),
			}),
		}),

		-- Punches the hole that turns the disc into a ring, and carries the label.
		Center = e("Frame", {
			Size = UDim2.fromScale(inner, inner),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			BackgroundColor3 = theme.color.surface,
			BorderSizePixel = 0,
			ZIndex = 2,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
			Label = if props.label
				then e("TextLabel", {
					Text = props.label,
					Size = UDim2.fromScale(0.8, 0.8),
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					BackgroundTransparency = 1,
					Font = theme.font.body,
					TextColor3 = theme.color.textHeading,
					TextScaled = true,
					ZIndex = 3,
				})
				else nil,
		}),
	})
end

return RadialGauge
