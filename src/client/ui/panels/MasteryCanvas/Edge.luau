--!strict
-- The line joining a node to the one it branches into: out of the parent's right side, across, and
-- into the child's left, as one elbowed stroke of light. Squared rather than diagonal so a tree of
-- several branches reads as rows, not a tangle.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local e = React.createElement

export type Props = {
	-- Content-space pixels: where the line leaves the parent and where it enters the child.
	from: Vector2,
	to: Vector2,
	color: Color3,
	-- What the line fades from and toward: the backdrop it is drawn over. Path2D's own Transparency
	-- is not writable from game scripts, so a faint or fading line is one whose colour is blended
	-- into what is behind it.
	background: Color3,
	-- How much of `color` the line shows once fully in, 0..1.
	strength: number,
	appear: any,
}

local function point(v: Vector2): Path2DControlPoint
	return Path2DControlPoint.new(UDim2.fromOffset(v.X, v.Y))
end

local function Edge(props: Props)
	local midX = (props.from.X + props.to.X) / 2
	local setPoints = React.useCallback(function(path: Path2D?)
		if path then
			path:SetControlPoints({
				point(props.from),
				point(Vector2.new(midX, props.from.Y)),
				point(Vector2.new(midX, props.to.Y)),
				point(props.to),
			})
		end
	end, { props.from, props.to })

	return e("Path2D", {
		Color3 = props.appear:map(function(a: number)
			return props.background:Lerp(props.color, props.strength * math.clamp(a, 0, 1))
		end),
		Thickness = 1.5,
		Visible = props.appear:map(function(a: number)
			return a > 0.01
		end),
		ZIndex = 2,
		ref = setPoints,
	})
end

return Edge
