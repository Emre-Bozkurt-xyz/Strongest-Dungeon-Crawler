--!strict
-- Placeholder item icons as line art, one per kind of item (decision 7 in
-- docs/tasks/ui-design-pass.md): until items have real icons, a slot shows what sort of thing it
-- holds -- a sword, a flask, a ring -- drawn in thin strokes of light like the rest of the System.
--
-- Each glyph is a list of strokes in a unit square (0,0 top-left), drawn by components/Glyph with
-- Path2D. Weapons lie on the same diagonal, hilt bottom-left, so a row of them reads as a set.

local ItemTypes = require(game:GetService("ReplicatedStorage").Shared.items.ItemTypes)

export type Point = { number }
export type Stroke = { points: { Point }, closed: boolean? }
export type Glyph = { Stroke }

local function line(...: Point): Stroke
	return { points = { ... } }
end

local function shape(...: Point): Stroke
	return { points = { ... }, closed = true }
end

-- A circle as a polygon, or an arc of one when `from`/`to` (degrees, 0 = right, clockwise) are
-- given. Enough segments to read as round at slot size.
local function arc(cx: number, cy: number, r: number, from: number?, to: number?): Stroke
	local a0 = from or 0
	local a1 = to or 360
	local segments = math.max(6, math.ceil(math.abs(a1 - a0) / 20))
	local points: { Point } = {}
	for i = 0, segments do
		local angle = math.rad(a0 + (a1 - a0) * i / segments)
		table.insert(points, { cx + r * math.cos(angle), cy + r * math.sin(angle) })
	end
	return { points = points, closed = from == nil }
end

-- Strokes run end to end as one closed outline.
local function joined(...: Stroke): Stroke
	local points: { Point } = {}
	for _, stroke in ipairs({ ... }) do
		for _, point in ipairs(stroke.points) do
			table.insert(points, point)
		end
	end
	return { points = points, closed = true }
end

local GLYPHS: { [string]: Glyph } = {
	-- Not items: the elements, for their mastery tracks.
	flame = {
		shape({ 0.5, 0.12 }, { 0.66, 0.34 }, { 0.75, 0.55 }, { 0.71, 0.72 }, { 0.59, 0.85 }, { 0.41, 0.85 }, { 0.29, 0.72 }, { 0.25, 0.55 }, { 0.35, 0.38 }, { 0.42, 0.5 }, { 0.46, 0.28 }),
		shape({ 0.5, 0.83 }, { 0.43, 0.71 }, { 0.5, 0.57 }, { 0.57, 0.71 }),
	},
	snowflake = {
		line({ 0.5, 0.12 }, { 0.5, 0.88 }),
		line({ 0.17, 0.31 }, { 0.83, 0.69 }),
		line({ 0.17, 0.69 }, { 0.83, 0.31 }),
		line({ 0.42, 0.2 }, { 0.5, 0.28 }, { 0.58, 0.2 }),
		line({ 0.42, 0.8 }, { 0.5, 0.72 }, { 0.58, 0.8 }),
	},
	-- Not an item: empty hands, for the Blunt mastery track.
	fist = {
		shape({ 0.28, 0.34 }, { 0.72, 0.34 }, { 0.78, 0.42 }, { 0.78, 0.66 }, { 0.66, 0.8 }, { 0.36, 0.8 }, { 0.24, 0.68 }, { 0.22, 0.44 }),
		line({ 0.39, 0.34 }, { 0.39, 0.5 }),
		line({ 0.5, 0.34 }, { 0.5, 0.5 }),
		line({ 0.61, 0.34 }, { 0.61, 0.5 }),
		line({ 0.24, 0.58 }, { 0.5, 0.6 }),
	},
	sword = {
		shape({ 0.86, 0.14 }, { 0.83, 0.26 }, { 0.43, 0.66 }, { 0.34, 0.57 }, { 0.74, 0.17 }),
		line({ 0.25, 0.53 }, { 0.47, 0.75 }),
		line({ 0.38, 0.62 }, { 0.2, 0.8 }),
		arc(0.17, 0.83, 0.04),
	},
	dagger = {
		shape({ 0.76, 0.24 }, { 0.73, 0.34 }, { 0.47, 0.6 }, { 0.4, 0.53 }, { 0.66, 0.27 }),
		line({ 0.32, 0.5 }, { 0.5, 0.68 }),
		line({ 0.43, 0.57 }, { 0.26, 0.74 }),
		arc(0.23, 0.77, 0.035),
	},
	axe = {
		line({ 0.2, 0.84 }, { 0.68, 0.2 }),
		shape({ 0.56, 0.2 }, { 0.72, 0.12 }, { 0.86, 0.2 }, { 0.9, 0.36 }, { 0.84, 0.48 }, { 0.68, 0.38 }),
	},
	mace = {
		line({ 0.2, 0.82 }, { 0.56, 0.46 }),
		arc(0.67, 0.34, 0.15),
		line({ 0.67, 0.13 }, { 0.67, 0.19 }),
		line({ 0.88, 0.34 }, { 0.82, 0.34 }),
		line({ 0.82, 0.19 }, { 0.78, 0.23 }),
	},
	wand = {
		line({ 0.2, 0.82 }, { 0.66, 0.36 }),
		line({ 0.24, 0.84 }, { 0.18, 0.78 }),
		line({ 0.76, 0.14 }, { 0.76, 0.38 }),
		line({ 0.64, 0.26 }, { 0.88, 0.26 }),
		line({ 0.69, 0.19 }, { 0.83, 0.33 }),
		line({ 0.83, 0.19 }, { 0.69, 0.33 }),
	},
	staff = {
		line({ 0.22, 0.9 }, { 0.66, 0.3 }),
		arc(0.74, 0.2, 0.1),
		arc(0.74, 0.2, 0.17, 150, 300),
	},
	bow = {
		arc(0.2, 0.8, 0.62, 270, 360),
		line({ 0.2, 0.18 }, { 0.82, 0.8 }),
		line({ 0.36, 0.64 }, { 0.62, 0.38 }),
		line({ 0.62, 0.38 }, { 0.56, 0.38 }),
		line({ 0.62, 0.38 }, { 0.62, 0.44 }),
	},
	shield = {
		shape({ 0.22, 0.18 }, { 0.78, 0.18 }, { 0.78, 0.48 }, { 0.72, 0.66 }, { 0.5, 0.86 }, { 0.28, 0.66 }, { 0.22, 0.48 }),
		line({ 0.5, 0.18 }, { 0.5, 0.86 }),
		line({ 0.22, 0.42 }, { 0.78, 0.42 }),
	},
	focus = {
		arc(0.5, 0.48, 0.24),
		arc(0.5, 0.48, 0.1),
		line({ 0.36, 0.84 }, { 0.64, 0.84 }),
		line({ 0.42, 0.72 }, { 0.36, 0.84 }),
		line({ 0.58, 0.72 }, { 0.64, 0.84 }),
	},
	quiver = {
		shape({ 0.32, 0.36 }, { 0.62, 0.36 }, { 0.62, 0.88 }, { 0.32, 0.88 }),
		line({ 0.4, 0.36 }, { 0.4, 0.14 }),
		line({ 0.54, 0.36 }, { 0.62, 0.16 }),
		line({ 0.36, 0.2 }, { 0.4, 0.14 }, { 0.44, 0.2 }),
		line({ 0.57, 0.19 }, { 0.62, 0.16 }, { 0.64, 0.22 }),
	},
	chest = {
		shape(
			{ 0.3, 0.14 },
			{ 0.42, 0.14 },
			{ 0.5, 0.26 },
			{ 0.58, 0.14 },
			{ 0.7, 0.14 },
			{ 0.88, 0.3 },
			{ 0.79, 0.44 },
			{ 0.72, 0.4 },
			{ 0.72, 0.86 },
			{ 0.28, 0.86 },
			{ 0.28, 0.4 },
			{ 0.21, 0.44 },
			{ 0.12, 0.3 }
		),
		line({ 0.5, 0.26 }, { 0.5, 0.86 }),
	},
	helm = {
		-- Dome, then down the cheek guards and in around the face opening.
		joined(
			arc(0.5, 0.5, 0.3, 180, 360),
			line({ 0.79, 0.84 }, { 0.6, 0.84 }, { 0.56, 0.62 }, { 0.44, 0.62 }, { 0.4, 0.84 }, { 0.21, 0.84 })
		),
		line({ 0.28, 0.5 }, { 0.72, 0.5 }),
		line({ 0.5, 0.5 }, { 0.5, 0.62 }),
	},
	gloves = {
		shape(
			{ 0.3, 0.86 },
			{ 0.3, 0.42 },
			{ 0.2, 0.3 },
			{ 0.26, 0.24 },
			{ 0.38, 0.34 },
			{ 0.38, 0.16 },
			{ 0.48, 0.16 },
			{ 0.48, 0.32 },
			{ 0.52, 0.12 },
			{ 0.62, 0.12 },
			{ 0.6, 0.34 },
			{ 0.68, 0.18 },
			{ 0.77, 0.2 },
			{ 0.72, 0.48 },
			{ 0.7, 0.86 }
		),
		line({ 0.3, 0.72 }, { 0.7, 0.72 }),
	},
	boots = {
		shape({ 0.3, 0.14 }, { 0.56, 0.14 }, { 0.56, 0.56 }, { 0.84, 0.66 }, { 0.86, 0.84 }, { 0.3, 0.84 }),
		line({ 0.3, 0.3 }, { 0.56, 0.3 }),
		line({ 0.3, 0.74 }, { 0.86, 0.74 }),
	},
	belt = {
		shape({ 0.1, 0.42 }, { 0.9, 0.42 }, { 0.9, 0.58 }, { 0.1, 0.58 }),
		shape({ 0.4, 0.34 }, { 0.6, 0.34 }, { 0.6, 0.66 }, { 0.4, 0.66 }),
		line({ 0.5, 0.5 }, { 0.6, 0.5 }),
	},
	amulet = {
		line({ 0.24, 0.12 }, { 0.38, 0.5 }, { 0.5, 0.56 }, { 0.62, 0.5 }, { 0.76, 0.12 }),
		shape({ 0.5, 0.56 }, { 0.62, 0.7 }, { 0.5, 0.86 }, { 0.38, 0.7 }),
	},
	ring = {
		arc(0.5, 0.62, 0.24),
		shape({ 0.5, 0.18 }, { 0.6, 0.29 }, { 0.5, 0.4 }, { 0.4, 0.29 }),
	},
	flask = {
		line({ 0.36, 0.12 }, { 0.64, 0.12 }),
		line({ 0.42, 0.12 }, { 0.42, 0.38 }),
		line({ 0.58, 0.12 }, { 0.58, 0.38 }),
		arc(0.5, 0.62, 0.26, -72, 252),
		line({ 0.27, 0.66 }, { 0.73, 0.66 }),
	},
	gem = {
		shape({ 0.3, 0.24 }, { 0.7, 0.24 }, { 0.86, 0.42 }, { 0.5, 0.86 }, { 0.14, 0.42 }),
		line({ 0.14, 0.42 }, { 0.86, 0.42 }),
		line({ 0.38, 0.42 }, { 0.5, 0.86 }, { 0.62, 0.42 }),
		line({ 0.38, 0.42 }, { 0.5, 0.24 }, { 0.62, 0.42 }),
	},
	scroll = {
		shape({ 0.26, 0.22 }, { 0.74, 0.22 }, { 0.74, 0.78 }, { 0.26, 0.78 }),
		line({ 0.18, 0.18 }, { 0.82, 0.18 }),
		line({ 0.18, 0.82 }, { 0.82, 0.82 }),
		line({ 0.36, 0.4 }, { 0.64, 0.4 }),
		line({ 0.36, 0.52 }, { 0.64, 0.52 }),
		line({ 0.36, 0.64 }, { 0.54, 0.64 }),
	},
	box = {
		shape({ 0.2, 0.36 }, { 0.8, 0.36 }, { 0.8, 0.82 }, { 0.2, 0.82 }),
		shape({ 0.16, 0.24 }, { 0.84, 0.24 }, { 0.84, 0.36 }, { 0.16, 0.36 }),
		line({ 0.44, 0.48 }, { 0.56, 0.48 }),
	},
}

local EQUIPMENT_CLASS_GLYPH: { [string]: string } = {
	body_armor = "chest",
	helmet = "helm",
	gloves = "gloves",
	boots = "boots",
	belt = "belt",
	amulet = "amulet",
	ring = "ring",
}

local OFFHAND_GLYPH: { [string]: string } = {
	shield = "shield",
	quiver = "quiver",
	catalyst = "focus",
	focus = "focus",
}

local CATEGORY_GLYPH: { [string]: string } = {
	consumable = "flask",
	material = "gem",
	quest = "scroll",
}

local ItemGlyphs = {}

-- The glyph id for an item: its weapon or offhand kind, else its equipment class, else its category.
function ItemGlyphs.forDef(def: ItemTypes.ItemDef?): string
	if not def then
		return "box"
	end
	local equipment = def.equipment
	if equipment then
		if equipment.weapon and GLYPHS[equipment.weapon.class] then
			return equipment.weapon.class
		end
		if equipment.offhand and OFFHAND_GLYPH[equipment.offhand.type] then
			return OFFHAND_GLYPH[equipment.offhand.type]
		end
		return EQUIPMENT_CLASS_GLYPH[equipment.class] or "box"
	end
	return CATEGORY_GLYPH[def.category] or "box"
end

function ItemGlyphs.get(id: string): Glyph
	return GLYPHS[id] or GLYPHS.box
end

function ItemGlyphs.ids(): { string }
	local ids = {}
	for id in pairs(GLYPHS) do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

return ItemGlyphs
