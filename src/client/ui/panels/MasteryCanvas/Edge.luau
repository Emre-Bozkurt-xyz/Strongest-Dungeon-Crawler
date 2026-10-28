--!strict
-- A line of the constellation, from a node to one it opens into (docs/planning/mastery-mind-space.md,
-- "Visual language").
--
-- Progress lives on the lines rather than in a header: a line into a locked node is grey and fills
-- with white from its start as the branch earns toward that node. An earned line is clean white, and
-- a Mastered branch's lines glow. A line into a fogged node is only a faint trace.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local e = React.createElement

local INK = Color3.fromRGB(238, 241, 246)
local GREY = Color3.fromRGB(93, 99, 111)

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

	return e(React.Fragment, nil, children)
end

return Edge
