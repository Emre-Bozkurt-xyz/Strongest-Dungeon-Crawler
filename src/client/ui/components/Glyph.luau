--!strict
-- Draws one of ItemGlyphs' line-art icons in a square field.
--
-- Path2D takes its points through a method rather than a property, so each stroke sets them from a
-- ref. Positions are scale, so the glyph fills whatever square it is given; the stroke width is in
-- pixels and goes through any UIScale above it like every other offset.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ItemGlyphs = require(script.Parent.Parent.glyphs.ItemGlyphs)

local e = React.createElement

export type Props = {
	glyph: string,
	color: Color3,
	thickness: number?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	zIndex: number?,
}

local function controlPoints(stroke: ItemGlyphs.Stroke): { Path2DControlPoint }
	local points = {}
	for _, point in ipairs(stroke.points) do
		table.insert(points, Path2DControlPoint.new(UDim2.fromScale(point[1], point[2])))
	end
	return points
end

local function Stroke(props: { stroke: ItemGlyphs.Stroke, color: Color3, thickness: number, zIndex: number? })
	local stroke = props.stroke
	local setPoints = React.useCallback(function(path: Path2D?)
		if path then
			path:SetControlPoints(controlPoints(stroke))
		end
	end, { stroke })

	return e("Path2D", {
		Color3 = props.color,
		Thickness = props.thickness,
		Closed = stroke.closed == true,
		ZIndex = props.zIndex,
		ref = setPoints,
	})
end

local function Glyph(props: Props)
	local strokes: { [string]: any } = {
		Ratio = e("UIAspectRatioConstraint", { AspectRatio = 1 }),
	}
	for index, stroke in ipairs(ItemGlyphs.get(props.glyph)) do
		strokes[`Stroke{index}`] = e(Stroke, {
			stroke = stroke,
			color = props.color,
			thickness = props.thickness or 1.5,
			zIndex = props.zIndex,
		})
	end

	return e("Frame", {
		Size = props.size or UDim2.fromScale(1, 1),
		Position = props.position or UDim2.fromScale(0.5, 0.5),
		AnchorPoint = props.anchorPoint or Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = props.zIndex,
	}, strokes)
end

return Glyph
