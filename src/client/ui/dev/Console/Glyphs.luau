--!strict
-- The console's line icons: the seven rail tabs, the search prompt, the real-save warning, and the
-- small controls of the character editor (carets, add / remove, edit, attunement, raise to max).
--
-- Roblox has no icon font, and the game's ItemGlyphs are item silhouettes, so these are drawn the
-- same way components/Glyph draws those (Path2D strokes in a unit square, 0,0 top-left) but kept
-- here, with the console, so console icons never land in the game's glyph set.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local e = React.createElement

type Point = { number }
type Stroke = { points: { Point }, closed: boolean? }

local function line(...: Point): Stroke
	return { points = { ... } }
end

local function shape(...: Point): Stroke
	return { points = { ... }, closed = true }
end

-- An ellipse, or an arc of one when `from`/`to` (degrees, 0 = right, clockwise) are given.
local function ellipse(cx: number, cy: number, rx: number, ry: number, from: number?, to: number?): Stroke
	local a0 = from or 0
	local a1 = to or 360
	local segments = math.max(6, math.ceil(math.abs(a1 - a0) / 15))
	local points: { Point } = {}
	for i = 0, segments do
		local angle = math.rad(a0 + (a1 - a0) * i / segments)
		table.insert(points, { cx + rx * math.cos(angle), cy + ry * math.sin(angle) })
	end
	return { points = points, closed = from == nil }
end

local function circle(cx: number, cy: number, r: number, from: number?, to: number?): Stroke
	return ellipse(cx, cy, r, r, from, to)
end

local GLYPHS: { [string]: { Stroke } } = {
	scenarios = {
		shape({ 0.12, 0.24 }, { 0.38, 0.14 }, { 0.62, 0.24 }, { 0.88, 0.14 }, { 0.88, 0.76 }, { 0.62, 0.86 }, { 0.38, 0.76 }, { 0.12, 0.86 }),
		line({ 0.38, 0.14 }, { 0.38, 0.76 }),
		line({ 0.62, 0.24 }, { 0.62, 0.86 }),
	},
	character = {
		circle(0.5, 0.32, 0.17),
		circle(0.5, 0.92, 0.34, 180, 360),
	},
	world = {
		circle(0.5, 0.5, 0.37),
		ellipse(0.5, 0.5, 0.16, 0.37),
		line({ 0.13, 0.5 }, { 0.87, 0.5 }),
	},
	debug = {
		ellipse(0.5, 0.58, 0.19, 0.25),
		circle(0.5, 0.3, 0.11, 180, 360),
		line({ 0.5, 0.36 }, { 0.5, 0.82 }),
		line({ 0.31, 0.46 }, { 0.14, 0.38 }),
		line({ 0.31, 0.6 }, { 0.12, 0.6 }),
		line({ 0.33, 0.74 }, { 0.16, 0.84 }),
		line({ 0.69, 0.46 }, { 0.86, 0.38 }),
		line({ 0.69, 0.6 }, { 0.88, 0.6 }),
		line({ 0.67, 0.74 }, { 0.84, 0.84 }),
	},
	commands = {
		shape({ 0.1, 0.18 }, { 0.9, 0.18 }, { 0.9, 0.82 }, { 0.1, 0.82 }),
		line({ 0.26, 0.38 }, { 0.4, 0.5 }, { 0.26, 0.62 }),
		line({ 0.48, 0.64 }, { 0.68, 0.64 }),
	},
	log = {
		line({ 0.12, 0.28 }, { 0.2, 0.28 }),
		line({ 0.12, 0.5 }, { 0.2, 0.5 }),
		line({ 0.12, 0.72 }, { 0.2, 0.72 }),
		line({ 0.32, 0.28 }, { 0.88, 0.28 }),
		line({ 0.32, 0.5 }, { 0.88, 0.5 }),
		line({ 0.32, 0.72 }, { 0.88, 0.72 }),
	},
	inspect = {
		circle(0.5, 0.6777, 0.4377, 204, 336),
		circle(0.5, 0.3223, 0.4377, 24, 156),
		circle(0.5, 0.5, 0.12),
	},
	search = {
		circle(0.43, 0.43, 0.25),
		line({ 0.61, 0.61 }, { 0.86, 0.86 }),
	},
	-- A select's open / closed caret; neither console face has ▾ or ▴.
	caretDown = {
		line({ 0.28, 0.4 }, { 0.5, 0.62 }, { 0.72, 0.4 }),
	},
	caretUp = {
		line({ 0.28, 0.6 }, { 0.5, 0.38 }, { 0.72, 0.6 }),
	},
	-- A collapsed accordion section.
	caretRight = {
		line({ 0.4, 0.28 }, { 0.62, 0.5 }, { 0.4, 0.72 }),
	},
	close = {
		line({ 0.28, 0.28 }, { 0.72, 0.72 }),
		line({ 0.72, 0.28 }, { 0.28, 0.72 }),
	},
	plus = {
		line({ 0.5, 0.24 }, { 0.5, 0.76 }),
		line({ 0.24, 0.5 }, { 0.76, 0.5 }),
	},
	minus = {
		line({ 0.24, 0.5 }, { 0.76, 0.5 }),
	},
	pencil = {
		shape({ 0.62, 0.18 }, { 0.82, 0.38 }, { 0.36, 0.84 }, { 0.16, 0.84 }, { 0.16, 0.64 }),
		line({ 0.52, 0.28 }, { 0.72, 0.48 }),
	},
	-- Attunement, as the mastery canvas marks it.
	star = {
		shape(
			{ 0.5, 0.1 },
			{ 0.61, 0.37 },
			{ 0.9, 0.39 },
			{ 0.68, 0.57 },
			{ 0.75, 0.86 },
			{ 0.5, 0.7 },
			{ 0.25, 0.86 },
			{ 0.32, 0.57 },
			{ 0.1, 0.39 },
			{ 0.39, 0.37 }
		),
	},
	-- Raise to the cap.
	max = {
		line({ 0.26, 0.2 }, { 0.74, 0.2 }),
		line({ 0.28, 0.58 }, { 0.5, 0.36 }, { 0.72, 0.58 }),
		line({ 0.5, 0.36 }, { 0.5, 0.84 }),
	},
	-- The return key (↵), which neither console face has.
	enter = {
		line({ 0.78, 0.22 }, { 0.78, 0.62 }, { 0.22, 0.62 }),
		line({ 0.4, 0.44 }, { 0.22, 0.62 }, { 0.4, 0.8 }),
	},
	warning = {
		shape({ 0.5, 0.12 }, { 0.9, 0.84 }, { 0.1, 0.84 }),
		line({ 0.5, 0.38 }, { 0.5, 0.6 }),
		line({ 0.5, 0.69 }, { 0.5, 0.74 }),
	},
}

local function StrokeView(props: { stroke: Stroke, color: Color3, thickness: number })
	local stroke = props.stroke
	local setPoints = React.useCallback(function(path: Path2D?)
		if path then
			local points = {}
			for _, point in ipairs(stroke.points) do
				table.insert(points, Path2DControlPoint.new(UDim2.fromScale(point[1], point[2])))
			end
			path:SetControlPoints(points)
		end
	end, { stroke })
	return e("Path2D", {
		Color3 = props.color,
		Thickness = props.thickness,
		Closed = stroke.closed == true,
		ref = setPoints,
	})
end

local Glyphs = {}

function Glyphs.has(name: string): boolean
	return GLYPHS[name] ~= nil
end

-- One icon in a square of `size` pixels.
function Glyphs.Glyph(props: {
	name: string,
	color: Color3,
	size: number,
	thickness: number?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
})
	local strokes: { [string]: any } = {}
	for index, stroke in ipairs(GLYPHS[props.name] or {}) do
		strokes[`s{index}`] = e(StrokeView, { stroke = stroke, color = props.color, thickness = props.thickness or 1.5 })
	end
	return e("Frame", {
		Size = UDim2.fromOffset(props.size, props.size),
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		LayoutOrder = props.layoutOrder,
		BackgroundTransparency = 1,
	}, strokes)
end

return Glyphs
