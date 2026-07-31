--!strict
-- Theme registry. Autoloads sibling theme modules and validates that each fills the full contract,
-- so a theme missing a role fails at startup rather than when a component using that role renders.

local ThemeTypes = require(script.ThemeTypes)

export type Theme = ThemeTypes.Theme
export type StyleRole = ThemeTypes.StyleRole

local Themes = {}

local DEFAULT_THEME_ID = "SoloLeveling"

local byId: { [string]: Theme } = {}
local orderedIds: { string } = {}

-- Every role a theme must define. Kept as data rather than derived from the type, because Luau
-- string-union types are not enumerable at runtime.
local REQUIRED_ROLES: { ThemeTypes.StyleRole } = {
	"PanelBackdrop",
	"PanelSurface",
	"AmbientPanel",
	"PanelBlock",
	"PanelHeading",
	"BodyText",
	"MutedText",
	"RequirementMet",
	"RequirementUnmet",
	"Slot",
	"SlotHovered",
	"SlotInset",
	"Socket",
	"SocketHovered",
	"TabActive",
	"TabInactive",
	"GaugeTrack",
	"GaugeFill",
}

local REQUIRED_COLORS = {
	"backdrop",
	"surface",
	"surfaceRaised",
	"surfaceOverlay",
	"slotSurface",
	"slotInset",
	"socketSurface",
	"socketStroke",
	"gaugeFill",
	"gaugeTrack",
	"skillSlotSurface",
	"skillSlotStroke",
	"skillSlotActiveStroke",
	"cooldownRadialTint",
	"gcdScrim",
	"gcdAccent",
	"castBlockedAccent",
	"iconReadyTint",
	"iconCooldownTint",
	"stroke",
	"strokeStrong",
	"textHeading",
	"textPrimary",
	"textMuted",
	"textDisabled",
	"textOnAccent",
	"accent",
	"accentFrom",
	"accentTo",
	"danger",
	"success",
}

local REQUIRED_METRICS = {
	"radiusPanel",
	"radiusControl",
	"strokeThin",
	"strokeThick",
	"strokePanel",
	"paddingSm",
	"paddingMd",
	"paddingLg",
}

local REQUIRED_FONTS = { "heading", "body", "action" }

local function register(theme: Theme, sourceName: string)
	assert(type(theme.id) == "string" and theme.id ~= "", `Theme at '{sourceName}' is missing an id`)
	assert(byId[theme.id] == nil, `Duplicate theme id '{theme.id}'`)

	for _, colorName in ipairs(REQUIRED_COLORS) do
		assert(
			typeof((theme.color :: any)[colorName]) == "Color3",
			`Theme '{theme.id}' is missing colour '{colorName}'`
		)
	end
	for _, metricName in ipairs(REQUIRED_METRICS) do
		assert(
			type((theme.metrics :: any)[metricName]) == "number",
			`Theme '{theme.id}' is missing metric '{metricName}'`
		)
	end
	for _, fontName in ipairs(REQUIRED_FONTS) do
		assert(
			typeof((theme.font :: any)[fontName]) == "EnumItem",
			`Theme '{theme.id}' is missing font '{fontName}'`
		)
	end
	for _, role in ipairs(REQUIRED_ROLES) do
		assert(type(theme.styles[role]) == "table", `Theme '{theme.id}' is missing style role '{role}'`)
	end

	byId[theme.id] = theme
	table.insert(orderedIds, theme.id)
end

for _, child in ipairs(script:GetChildren()) do
	if child:IsA("ModuleScript") and child.Name ~= "ThemeTypes" then
		register(require(child) :: Theme, child:GetFullName())
	end
end

table.sort(orderedIds)

assert(byId[DEFAULT_THEME_ID] ~= nil, `Themes: required default theme '{DEFAULT_THEME_ID}' is missing`)

function Themes.get(id: string): Theme?
	return byId[id]
end

function Themes.getDefault(): Theme
	return byId[DEFAULT_THEME_ID]
end

function Themes.list(): { Theme }
	local out: { Theme } = {}
	for _, id in ipairs(orderedIds) do
		table.insert(out, byId[id])
	end
	return out
end

return Themes
