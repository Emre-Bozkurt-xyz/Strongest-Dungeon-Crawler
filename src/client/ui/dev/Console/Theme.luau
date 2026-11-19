--!strict
-- The dev console's own look: a neutral graphite command palette, apart from the game's System
-- theme so a developer tool never reads as part of the game, and so the game's theme can change
-- without the console following it.
--
-- Every console component reads its colours, faces, type sizes, spacing and radii from here; a new
-- console screen built from Controls matches without any styling of its own.
--
-- Sizes are screen pixels for a dock 460-600px wide at 1080p: body text at 16, secondary at 14,
-- nothing under 13. Builder Sans is Roblox's own clean UI sans and Builder Mono its matching
-- monospace, so the two sit on the same metrics; mono carries ids, commands and values.

local Theme = {}

local function hex(value: string): Color3
	return Color3.fromHex(value)
end

Theme.color = {
	-- Surfaces.
	panel = hex("#111113"),
	raised = hex("#18181b"),
	selected = hex("#17171a"),
	hover = hex("#1d1d21"),
	suggestion = hex("#1b1b1f"),
	-- Lines: dividers between regions, the panel's own edge, outlines of controls.
	divider = hex("#222227"),
	edge = hex("#26262b"),
	outline = hex("#2c2c32"),
	buttonOutline = hex("#303036"),
	strongOutline = hex("#55555e"),
	-- Ink.
	text = hex("#ededef"),
	secondary = hex("#9a9aa3"),
	dim = hex("#6a6a73"),
	buttonText = hex("#d6d6da"),
	chipText = hex("#a0a0a8"),
	kbdText = hex("#8b8b94"),
	-- Ink on the one filled (primary) button.
	onPrimary = hex("#111113"),
	-- State: one green for on / loaded / ok, one red family for failure and the real save.
	ok = hex("#3ecf8e"),
	okText = hex("#7fd9a8"),
	bad = hex("#f2a3a3"),
	badSurface = hex("#241213"),
	badEdge = hex("#4a2427"),
	badMuted = hex("#b98a8a"),
	-- Client warnings in the output: amber, apart from both of the above.
	warn = hex("#e3c27a"),
	-- Switch track when off, gauge track.
	off = hex("#34343a"),
	track = hex("#26262b"),
}

local SANS = "rbxasset://fonts/families/BuilderSans.json"
local MONO = "rbxasset://fonts/families/BuilderMono.json"

-- Two weights only: regular for reading, medium for titles and anything picked.
Theme.font = {
	body = Font.new(SANS, Enum.FontWeight.Regular),
	medium = Font.new(SANS, Enum.FontWeight.Medium),
	mono = Font.new(MONO, Enum.FontWeight.Regular),
}

Theme.size = {
	body = 16,
	secondary = 14,
	small = 13,
	mono = 15,
	monoSmall = 14,
}

Theme.space = {
	-- Left and right inset of everything in the content column.
	pad = 16,
	gap = 8,
	-- One selectable row, one line of controls.
	row = 34,
	control = 28,
	-- Room above a section label, and between a label and its first row.
	sectionTop = 14,
	sectionBottom = 4,
}

Theme.radius = {
	small = UDim.new(0, 4),
	control = UDim.new(0, 6),
	large = UDim.new(0, 8),
	pill = UDim.new(1, 0),
}

return Theme
