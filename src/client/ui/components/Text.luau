--!strict
-- Themed text. Every string in the UI goes through here so type styling lives in the theme rather
-- than scattered across panels (Guardrail 3 and 9).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ThemeContext = require(script.Parent.Parent.hooks.ThemeContext)
local Themes = require(ReplicatedStorage.Shared.ui.themes)

export type Props = {
	text: string,
	role: Themes.StyleRole?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
	alignX: Enum.TextXAlignment?,
	alignY: Enum.TextYAlignment?,
	textSize: number?,
	richText: boolean?,
	wrapped: boolean?,
	automaticSize: Enum.AutomaticSize?,
	-- Outline on the glyphs themselves. The design uses this on the item title for a faint glow.
	glow: boolean?,
	-- Escape hatch for one-off deviations; overrides the resolved role.
	props: { [string]: any }?,
}

local function Text(props: Props)
	local theme = ThemeContext.useTheme()
	local styled = ThemeContext.useStyle(props.role or "BodyText", props.props)

	local merged: { [string]: any } = table.clone(styled)
	merged.Text = props.text
	merged.Size = props.size or UDim2.new(1, 0, 0, 20)
	merged.Position = props.position
	merged.AnchorPoint = props.anchorPoint
	merged.LayoutOrder = props.layoutOrder
	merged.TextXAlignment = props.alignX or Enum.TextXAlignment.Left
	merged.TextYAlignment = props.alignY or Enum.TextYAlignment.Center
	if props.richText then
		merged.RichText = true
	end
	if props.wrapped then
		merged.TextWrapped = true
	end
	if props.automaticSize then
		merged.AutomaticSize = props.automaticSize
	end
	-- An explicit size means the caller wants that size, so scaling has to be turned off -- the
	-- theme roles set TextScaled for the headline cases that do want to fill their box.
	if props.textSize then
		merged.TextSize = props.textSize
		merged.TextScaled = false
	end

	local children: { [string]: any }? = nil
	if props.glow then
		children = {
			Glow = React.createElement("UIStroke", {
				Color = theme.color.strokeStrong,
				Thickness = theme.metrics.strokeThin,
				Transparency = 0.5,
				LineJoinMode = Enum.LineJoinMode.Round,
			}),
		}
	end

	return React.createElement("TextLabel", merged, children)
end

return Text
