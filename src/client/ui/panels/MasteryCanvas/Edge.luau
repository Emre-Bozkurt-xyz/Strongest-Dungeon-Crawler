--!strict
-- A line of the constellation, from a node to one it opens into (docs/planning/mastery-mind-space.md,
-- "Visual language").
--
-- Progress lives on the lines rather than in a header: a line into a locked node is grey and fills
-- with white from its start as the branch earns toward that node. An earned line is clean white, and
-- a Mastered branch's lines glow. A line into a fogged node is only a faint trace.
--
-- Pointing at a line shows its numbers (the branch's XP and what the next node takes), for when the
-- fill alone is too coarse to tell how close it is. A one-pixel line is no target, so a row of
-- invisible squares along it takes the hover, stopping short of the nodes at either end.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local ThemeContext = require(script.Parent.Parent.Parent.hooks.ThemeContext)

local e = React.createElement

local INK = Color3.fromRGB(238, 241, 246)
local GREY = Color3.fromRGB(93, 99, 111)
-- The hover target: squares this wide, this far apart, kept this far from the nodes.
local HIT_SIZE = 24
local HIT_STEP = 16
local HIT_END_CLEARANCE = 34

export type State = "earned" | "mastered" | "pending" | "fogged"

export type Props = {
	-- Content-space centres of the two nodes.
	from: Vector2,
	to: Vector2,
	state: State,
	-- Pending lines: 0..1 filled from `from`.
	fill: number,
	-- 0..1 binding: this line's part of the entrance.
	appear: any,
	-- What pointing at the line shows; nil for a line with nothing to tell (a fogged one).
	label: string?,
	hovered: boolean,
	onHover: (hovering: boolean) -> (),
}

-- One straight stroke from `from` along `direction` for `length` pixels.
local function stroke(from: Vector2, direction: Vector2, length: number, props: { [string]: any })
	local centre = from + direction * (length / 2)
	local merged: { [string]: any } = {
		Size = UDim2.fromOffset(length, props.thickness),
		Position = UDim2.fromOffset(centre.X, centre.Y),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Rotation = math.deg(math.atan2(direction.Y, direction.X)),
		BackgroundColor3 = props.color,
		BackgroundTransparency = props.transparency,
		BorderSizePixel = 0,
		ZIndex = 1,
	}
	return e("Frame", merged)
end

local function Edge(props: Props)
	local theme = ThemeContext.useTheme()
	local delta = props.to - props.from
	local length = delta.Magnitude
	if length < 1 then
		return nil
	end
	local direction = delta.Unit
	local function fade(base: number)
		return props.appear:map(function(a: number)
			return 1 - (1 - base) * math.clamp(a, 0, 1)
		end)
	end

	local children: { [string]: any } = {}
	if props.state == "earned" then
		children.Line = stroke(props.from, direction, length, { thickness = 1, color = INK, transparency = fade(0.3) })
	elseif props.state == "mastered" then
		children.Glow = stroke(props.from, direction, length, { thickness = 5, color = INK, transparency = fade(0.88) })
		children.Line = stroke(props.from, direction, length, { thickness = 1.5, color = INK, transparency = fade(0.05) })
	elseif props.state == "pending" then
		children.Line = stroke(props.from, direction, length, { thickness = 1, color = GREY, transparency = fade(0.3) })
		if props.fill > 0 then
			children.Fill = stroke(
				props.from,
				direction,
				length * math.clamp(props.fill, 0, 1),
				{ thickness = 1, color = INK, transparency = fade(0.15) }
			)
		end
	else
		children.Line = stroke(props.from, direction, length, { thickness = 1, color = GREY, transparency = fade(0.78) })
	end

	local label = props.label
	if label then
		local distance = HIT_END_CLEARANCE
		local index = 0
		while distance <= length - HIT_END_CLEARANCE do
			index += 1
			local at = props.from + direction * distance
			children[`Hit{index}`] = e("Frame", {
				Size = UDim2.fromOffset(HIT_SIZE, HIT_SIZE),
				Position = UDim2.fromOffset(at.X, at.Y),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				ZIndex = 1,
				[React.Event.MouseEnter] = function()
					props.onHover(true)
				end,
				[React.Event.MouseLeave] = function()
					props.onHover(false)
				end,
			})
			distance += HIT_STEP
		end
		if props.hovered then
			local middle = props.from + delta / 2
			children.Label = e("TextLabel", {
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 34),
				-- Above the line, clear of it.
				Position = UDim2.fromOffset(middle.X, middle.Y - 14),
				AnchorPoint = Vector2.new(0.5, 1),
				BackgroundColor3 = Color3.fromRGB(6, 7, 10),
				BackgroundTransparency = 0.08,
				BorderSizePixel = 0,
				Text = label,
				FontFace = theme.face.bodyBold,
				TextSize = 20,
				TextColor3 = INK,
				ZIndex = 6,
			}, {
				Padding = e("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }),
				Stroke = e("UIStroke", { Color = INK, Thickness = 1, Transparency = 0.75 }),
			})
		end
	end

	return e(React.Fragment, nil, children)
end

return Edge
