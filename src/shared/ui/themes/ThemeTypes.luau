--!strict
-- Theme contract. Every theme fills the same shape, so swapping one for another is a value swap
-- rather than a code change (R8 in docs/tasks/ui-migration-plan.md).
--
-- Colours are declared semantically, never by appearance: `textMuted`, not `gray`. A component
-- asking for "the muted text colour" keeps working when a theme decides muted text is blue.

local ThemeTypes = {}

export type ThemeColors = {
	-- Backgrounds, darkest to lightest. `backdrop` is the outermost wash a panel floats on; the
	-- panels are deliberately layered translucent rather than one opaque fill, which is where the
	-- depth in the Studio design came from.
	backdrop: Color3,
	surface: Color3,
	surfaceRaised: Color3,
	surfaceOverlay: Color3,

	-- Item slot chrome: the outer tinted square and the inset the icon sits in.
	slotSurface: Color3,
	slotInset: Color3,

	-- Equipment paper-doll sockets, which read as cut-outs rather than filled slots: a pale face
	-- behind a heavy dark outline.
	socketSurface: Color3,
	socketStroke: Color3,

	-- Gauges (health, mana, stamina, cast bars).
	gaugeFill: Color3,
	gaugeTrack: Color3,

	-- HUD skill bar. Deliberately outside the panel palette: the bar sits over open gameplay with no
	-- surface behind it, so it reads against the world rather than against a panel.
	skillSlotSurface: Color3,
	skillSlotStroke: Color3,
	skillSlotActiveStroke: Color3,
	cooldownRadialTint: Color3,
	gcdScrim: Color3,
	gcdAccent: Color3,
	castBlockedAccent: Color3,
	iconReadyTint: Color3,
	iconCooldownTint: Color3,

	stroke: Color3,
	strokeStrong: Color3,

	textHeading: Color3,
	textPrimary: Color3,
	textMuted: Color3,
	textDisabled: Color3,
	-- Sits on `accent`/the control gradient, which are light, so this is dark.
	textOnAccent: Color3,

	accent: Color3,
	accentFrom: Color3,
	accentTo: Color3,
	danger: Color3,
	success: Color3,
}

-- Pixel values, kept narrow. Layout is scale-based throughout this project; these exist only where
-- Roblox forces an offset.
export type ThemeMetrics = {
	radiusPanel: number,
	radiusControl: number,
	strokeThin: number,
	strokeThick: number,
	-- The heavy translucent outline that separates each block in the design.
	strokePanel: number,
	paddingSm: number,
	paddingMd: number,
	paddingLg: number,
}

export type ThemeFonts = {
	heading: Enum.Font,
	body: Enum.Font,
	action: Enum.Font,
}

-- Named roles. Adding one here forces every theme to answer for it, which is the point: a role that
-- only one theme defines is a role components cannot safely use.
export type StyleRole =
	-- The outer wash. A panel is `PanelBackdrop` containing `PanelSurface`, not one flat fill.
	"PanelBackdrop"
	| "PanelSurface"
	-- Always-on gameplay panel. Higher contrast than PanelSurface because it competes with the world
	-- behind it rather than a dimmed backdrop (R7).
	| "AmbientPanel"
	-- A bordered block inside a panel: the icon well, the title bar, the info scroll.
	| "PanelBlock"
	| "PanelHeading"
	| "BodyText"
	| "MutedText"
	| "RequirementMet"
	| "RequirementUnmet"
	| "Slot"
	| "SlotHovered"
	-- The inset inside a slot that the icon sits on.
	| "SlotInset"
	-- Equipment paper-doll socket, distinct from an inventory Slot.
	| "Socket"
	| "SocketHovered"
	| "TabActive"
	| "TabInactive"
	| "GaugeTrack"
	| "GaugeFill"

export type StyleProps = { [string]: any }

export type Theme = {
	id: string,
	label: string,
	color: ThemeColors,
	metrics: ThemeMetrics,
	font: ThemeFonts,
	styles: { [StyleRole]: StyleProps },
}

return ThemeTypes
