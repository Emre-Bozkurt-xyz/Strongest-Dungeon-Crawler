--!strict
-- Theme delivery. Components read the theme through `useTheme`/`useStyle` and never require a theme
-- module directly (Guardrail 9), so a subtree can be re-themed by wrapping it in another provider.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Themes = require(ReplicatedStorage.Shared.ui.themes)

type Theme = Themes.Theme
type StyleRole = Themes.StyleRole

local ThemeContext = React.createContext(Themes.getDefault())

local Exports = {}

Exports.Provider = ThemeContext.Provider

function Exports.useTheme(): Theme
	return React.useContext(ThemeContext)
end

-- Resolved props for a role, with per-call overrides applied on top.
--
-- Overrides always win, so a component can adopt a role and still set `Text`, `Size`, or deviate on
-- one property without abandoning the role entirely.
function Exports.useStyle(role: StyleRole, overrides: { [string]: any }?): { [string]: any }
	local theme = Exports.useTheme()
	return React.useMemo(function()
		local base = theme.styles[role]
		local props: { [string]: any } = {}
		if base then
			for key, value in pairs(base) do
				props[key] = value
			end
		else
			warn(`useStyle: theme '{theme.id}' has no style role '{role}'`)
		end
		if overrides then
			for key, value in pairs(overrides) do
				props[key] = value
			end
		end
		return props
	end, { theme :: any, role :: any, overrides :: any })
end

return Exports
