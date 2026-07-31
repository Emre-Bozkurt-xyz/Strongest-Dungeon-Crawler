--!strict
-- Ported from the Studio design: the `Tokens` stylesheet in Design.rbxmx plus the per-panel styling
-- authored directly on ItemInspectPanel.rbxmx (decoded 2026-07-30).
--
-- `raw` is the palette exactly as authored; `color` maps it onto semantic names. Components only
-- ever see `color`, so re-pointing `textPrimary` at a different swatch is a one-line change here
-- rather than a search across every panel.
--
-- The transparencies matter as much as the hues: the design is layered translucent surfaces
-- (backdrop 0.5 over root 0.45 over fill 0.65) with a heavy half-transparent outline on each block.
-- Flattening any of that to an opaque fill loses the entire look.

local ThemeTypes = require(script.Parent.ThemeTypes)

local raw = {
	Purple = Color3.fromRGB(46, 0, 115),
	PurpleDark = Color3.fromRGB(36, 24, 53),
	PurpleDarker = Color3.fromRGB(13, 0, 33),
	PurpleFill = Color3.fromRGB(52, 14, 68),
	Gray = Color3.fromRGB(92, 88, 94),
	GrayDark = Color3.fromRGB(52, 49, 53),
	GrayLight = Color3.fromRGB(160, 153, 163),
	BlueLight = Color3.fromRGB(185, 206, 232),
	BlueGlow = Color3.fromRGB(96, 177, 232),
	BluePale = Color3.fromRGB(200, 240, 249),
	Content = Color3.fromRGB(236, 236, 236),
	AccentFrom = Color3.fromRGB(150, 113, 195),
	AccentTo = Color3.fromRGB(205, 206, 255),
	Ink = Color3.fromRGB(16, 14, 50),
	SlotPurple = Color3.fromRGB(47, 3, 97),
	SlotInset = Color3.fromRGB(42, 0, 63),
	SocketFace = Color3.fromRGB(122, 131, 172),
	SocketOutline = Color3.fromRGB(10, 8, 22),
	GaugeFill = Color3.fromRGB(193, 213, 231),
	GaugeTrack = Color3.fromRGB(205, 229, 252),
}

local color: ThemeTypes.ThemeColors = {
	backdrop = raw.Purple,
	surface = raw.PurpleDarker,
	surfaceRaised = raw.PurpleFill,
	surfaceOverlay = raw.GrayDark,

	slotSurface = raw.SlotPurple,
	slotInset = raw.SlotInset,

	socketSurface = raw.SocketFace,
	socketStroke = raw.SocketOutline,

	gaugeFill = raw.GaugeFill,
	gaugeTrack = raw.GaugeTrack,

	skillSlotSurface = Color3.fromRGB(68, 68, 68),
	skillSlotStroke = Color3.fromRGB(58, 58, 58),
	skillSlotActiveStroke = Color3.fromRGB(212, 236, 0),
	cooldownRadialTint = Color3.fromRGB(170, 194, 217),
	gcdScrim = Color3.fromRGB(0, 0, 0),
	gcdAccent = Color3.fromRGB(212, 236, 0),
	castBlockedAccent = Color3.fromRGB(185, 37, 37),
	iconReadyTint = Color3.fromRGB(255, 255, 255),
	iconCooldownTint = Color3.fromRGB(180, 180, 180),

	stroke = raw.BlueLight,
	strokeStrong = raw.BlueGlow,

	textHeading = raw.BluePale,
	textPrimary = raw.Content,
	textMuted = raw.GrayLight,
	textDisabled = raw.Gray,
	textOnAccent = raw.Ink,

	accent = raw.AccentFrom,
	accentFrom = raw.AccentFrom,
	accentTo = raw.AccentTo,
	-- No danger/success token existed in the Studio palette; these are new and deliberately outside
	-- the purple family so a failure state cannot be mistaken for chrome.
	danger = Color3.fromRGB(220, 84, 84),
	-- The bonus-value green the Studio panels use for "(+N)" readouts.
	success = Color3.fromRGB(0, 214, 0),
}

local metrics: ThemeTypes.ThemeMetrics = {
	radiusPanel = 12,
	radiusControl = 8,
	strokeThin = 1,
	strokeThick = 2,
	strokePanel = 3.5,
	paddingSm = 8,
	paddingMd = 16,
	paddingLg = 24,
}

local font: ThemeTypes.ThemeFonts = {
	heading = Enum.Font.SourceSansBold,
	body = Enum.Font.SourceSans,
	action = Enum.Font.FredokaOne,
}

local styles: { [ThemeTypes.StyleRole]: ThemeTypes.StyleProps } = {
	PanelBackdrop = {
		BackgroundColor3 = color.backdrop,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
	},
	PanelSurface = {
		BackgroundColor3 = color.surface,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
	},
	-- Sits over live gameplay rather than a dimmed backdrop (R7), so it is more solid than
	-- PanelSurface -- but not opaque. A fully opaque slab beside the character reads as a sticker
	-- pasted on the world; the Studio original was translucent for that reason.
	AmbientPanel = {
		BackgroundColor3 = color.surface,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
	},
	PanelBlock = {
		BackgroundColor3 = color.surfaceRaised,
		BackgroundTransparency = 0.65,
		BorderSizePixel = 0,
	},
	PanelHeading = {
		BackgroundTransparency = 1,
		TextColor3 = color.textHeading,
		TextScaled = true,
		Font = font.heading,
	},
	BodyText = {
		BackgroundTransparency = 1,
		TextColor3 = color.textPrimary,
		TextScaled = true,
		Font = font.body,
	},
	MutedText = {
		BackgroundTransparency = 1,
		TextColor3 = color.textMuted,
		TextScaled = true,
		Font = font.body,
	},
	RequirementMet = {
		BackgroundTransparency = 1,
		TextColor3 = color.textMuted,
		TextScaled = true,
		Font = font.body,
	},
	RequirementUnmet = {
		BackgroundTransparency = 1,
		TextColor3 = color.danger,
		TextScaled = true,
		Font = font.heading,
	},
	Slot = {
		BackgroundColor3 = color.slotSurface,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
	},
	SlotHovered = {
		BackgroundColor3 = color.slotSurface,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
	},
	SlotInset = {
		BackgroundColor3 = color.slotInset,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
	},
	Socket = {
		BackgroundColor3 = color.socketSurface,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
	},
	SocketHovered = {
		BackgroundColor3 = color.socketSurface,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
	},
	TabActive = {
		BackgroundTransparency = 1,
		TextColor3 = color.textHeading,
		TextScaled = true,
		Font = font.heading,
	},
	TabInactive = {
		BackgroundTransparency = 1,
		TextColor3 = color.textMuted,
		TextScaled = true,
		Font = font.body,
	},
	GaugeTrack = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	},
	GaugeFill = {
		BackgroundColor3 = color.gaugeFill,
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
	},
}

local theme: ThemeTypes.Theme = {
	id = "SoloLeveling",
	label = "Solo Leveling",
	color = color,
	metrics = metrics,
	font = font,
	styles = styles,
}

return theme
