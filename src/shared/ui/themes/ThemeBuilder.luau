--!strict
-- Builds a full theme in the System style from a small palette.
--
-- The System is projected light on near-black: surfaces are dark and translucent, and everything
-- meaningful -- edges, text, state -- is drawn in light. Structure is drawn in neutral white light and
-- the skin's colour is kept for focus (hover, selection, what wants attention), so colour always means
-- something rather than tinting the whole panel. A skin only supplies a palette; one that restyles the chrome can override
-- `chrome` after building. Not a theme itself, so the registry skips it.

local ThemeTypes = require(script.Parent.ThemeTypes)

export type Palette = {
	-- Surfaces, darkest first.
	void: Color3,
	deep: Color3,
	-- Neutral light the structure is drawn in (brackets, rules, outlines), and a dimmer rest state.
	line: Color3,
	lineDim: Color3,
	-- The skin's colour, for focus only, and its bright lit state.
	focus: Color3,
	glow: Color3,
	ink: Color3,
	inkMuted: Color3,
	inkFaint: Color3,
	alert: Color3,
	warn: Color3,
	ok: Color3,
	rarity: ThemeTypes.ThemeRarity,
}

local TITILLIUM = Font.fromEnum(Enum.Font.TitilliumWeb).Family

local function build(id: string, label: string, p: Palette): ThemeTypes.Theme
	local color: ThemeTypes.ThemeColors = {
		backdrop = p.void,
		surface = p.void,
		surfaceRaised = p.deep,
		surfaceOverlay = p.deep,

		slotSurface = p.deep,
		slotInset = p.void,

		socketSurface = p.deep,
		socketStroke = p.lineDim,

		gaugeFill = p.line,
		gaugeTrack = p.deep,

		skillSlotSurface = p.void,
		skillSlotStroke = p.lineDim,
		skillSlotActiveStroke = p.focus,
		cooldownRadialTint = p.line,
		gcdScrim = Color3.new(0, 0, 0),
		gcdAccent = p.line,
		castBlockedAccent = p.alert,
		iconReadyTint = Color3.new(1, 1, 1),
		iconCooldownTint = p.inkMuted,

		stroke = p.line,
		strokeStrong = p.focus,

		textHeading = p.ink,
		textPrimary = p.ink,
		textMuted = p.inkMuted,
		textDisabled = p.inkFaint,
		textOnAccent = p.void,

		accent = p.focus,
		accentFrom = p.focus,
		accentTo = p.glow,
		danger = p.alert,
		success = p.ok,
	}

	-- Hairlines and near-square corners: light drawn as thin lines, not padded rounded boxes.
	local metrics: ThemeTypes.ThemeMetrics = {
		radiusPanel = 2,
		radiusControl = 2,
		strokeThin = 1,
		strokeThick = 2,
		strokePanel = 1,
		paddingSm = 8,
		paddingMd = 16,
		paddingLg = 24,
	}

	local font: ThemeTypes.ThemeFonts = {
		heading = Enum.Font.Michroma,
		body = Enum.Font.TitilliumWeb,
		action = Enum.Font.Michroma,
	}

	local face: ThemeTypes.ThemeFaces = {
		display = Font.fromEnum(Enum.Font.Michroma),
		body = Font.new(TITILLIUM, Enum.FontWeight.Regular),
		bodyBold = Font.new(TITILLIUM, Enum.FontWeight.Bold),
		mono = Font.fromEnum(Enum.Font.RobotoMono),
	}

	local typeScale: ThemeTypes.ThemeTypeScale = {
		label = 12,
		small = 14,
		body = 17,
		title = 20,
		display = 24,
	}

	local chrome: ThemeTypes.ThemeChrome = {
		panelBracket = { length = 28, thickness = 3 },
		bracket = { length = 10, thickness = 2 },
		edgeTransparency = 0.78,
		fillTransparency = 0.3,
		fillFade = 0.45,
	}

	local motion: ThemeTypes.ThemeMotion = {
		snap = { frequency = 6, damping = 1 },
		settle = { frequency = 4, damping = 1 },
		drift = { frequency = 1.2, damping = 1 },
	}

	local styles: { [ThemeTypes.StyleRole]: ThemeTypes.StyleProps } = {
		PanelBackdrop = {
			BackgroundColor3 = p.void,
			BackgroundTransparency = chrome.fillTransparency,
			BorderSizePixel = 0,
		},
		-- Panels are one translucent layer in this style, so the inner surface adds no fill of its
		-- own on top of the backdrop.
		PanelSurface = {
			BackgroundColor3 = p.void,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		},
		-- Over live gameplay rather than a dimmed backdrop (R7): a touch more solid than a menu panel.
		AmbientPanel = {
			BackgroundColor3 = p.void,
			BackgroundTransparency = 0.22,
			BorderSizePixel = 0,
		},
		PanelBlock = {
			BackgroundColor3 = p.deep,
			BackgroundTransparency = 0.55,
			BorderSizePixel = 0,
		},
		PanelHeading = {
			BackgroundTransparency = 1,
			TextColor3 = p.ink,
			TextScaled = true,
			FontFace = face.display,
		},
		BodyText = {
			BackgroundTransparency = 1,
			TextColor3 = p.ink,
			TextScaled = true,
			FontFace = face.body,
		},
		MutedText = {
			BackgroundTransparency = 1,
			TextColor3 = p.inkMuted,
			TextScaled = true,
			FontFace = face.body,
		},
		RequirementMet = {
			BackgroundTransparency = 1,
			TextColor3 = p.inkMuted,
			TextScaled = true,
			FontFace = face.body,
		},
		RequirementUnmet = {
			BackgroundTransparency = 1,
			TextColor3 = p.alert,
			TextScaled = true,
			FontFace = face.bodyBold,
		},
		Slot = {
			BackgroundColor3 = p.deep,
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
		},
		SlotHovered = {
			BackgroundColor3 = p.deep,
			BackgroundTransparency = 0.05,
			BorderSizePixel = 0,
		},
		SlotInset = {
			BackgroundColor3 = p.void,
			BackgroundTransparency = 0.6,
			BorderSizePixel = 0,
		},
		Socket = {
			BackgroundColor3 = p.deep,
			BackgroundTransparency = 0.45,
			BorderSizePixel = 0,
		},
		SocketHovered = {
			BackgroundColor3 = p.deep,
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
		},
		TabActive = {
			BackgroundTransparency = 1,
			TextColor3 = p.ink,
			TextScaled = true,
			FontFace = face.display,
		},
		TabInactive = {
			BackgroundTransparency = 1,
			TextColor3 = p.inkMuted,
			TextScaled = true,
			FontFace = face.display,
		},
		GaugeTrack = {
			BackgroundColor3 = p.deep,
			BackgroundTransparency = 0.2,
			BorderSizePixel = 0,
		},
		GaugeFill = {
			BackgroundColor3 = p.line,
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
		},
	}

	return {
		id = id,
		label = label,
		color = color,
		metrics = metrics,
		font = font,
		face = face,
		type = typeScale,
		rarity = p.rarity,
		chrome = chrome,
		motion = motion,
		transitions = {
			reveal = 0.24,
			conceal = 0.14,
			switchDelay = 0.08,
		},
		styles = styles,
	}
end

return build
