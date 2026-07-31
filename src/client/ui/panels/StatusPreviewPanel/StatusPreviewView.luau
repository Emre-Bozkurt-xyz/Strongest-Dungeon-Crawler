--!strict
-- Presentational half of the always-on status readout: HP and MP stacked on the left, the stamina
-- ring at the right -- ported from docs/ui/StatusPreviewPanel.rbxmx, which has no reference
-- screenshot (docs/ui/*OTS.png covers System, Inventory and Equipment only), so the export's own
-- proportions are the spec.
--
-- The outer frame is a single AmbientPanel (R7), not PanelShell's backdrop+body pair: the export has
-- one Frame (StatusPanel) with its own fill and stroke, not a wash behind a card, and doubling that
-- would add a visual layer the original never had. `corner = false` matches it too -- StatusPanel
-- carries a UIStroke but no UICorner, so unlike every menu panel its corners stay square.
--
-- HealthIcon/ManaIcon carry no Image in the export (the asset was never assigned in Studio), so this
-- reuses the ids SystemPanel's StatusView established for the same two vitals.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local Panel = require(script.Parent.Parent.Parent.components.Panel)
local VitalGauge = require(script.Parent.Parent.Parent.components.VitalGauge)
local RadialGauge = require(script.Parent.Parent.Parent.components.RadialGauge)

local ThemeContext = require(script.Parent.Parent.Parent.hooks.ThemeContext)
local useTweenedNumber = require(script.Parent.Parent.Parent.hooks.useTweenedNumber)

local Selector = require(script.Parent.Parent.Parent.selectors.systemStatus)

local e = React.createElement

export type Props = {
	vitals: { Selector.VitalView },
}

local HEART_ICON = "rbxassetid://100398419080154"
local DROPLET_ICON = "rbxassetid://109364647302001"

local function findVital(vitals: { Selector.VitalView }, label: string): Selector.VitalView?
	for _, vital in ipairs(vitals) do
		if vital.label == label then
			return vital
		end
	end
	return nil
end

local function StatusPreviewView(props: Props)
	local theme = ThemeContext.useTheme()

	local health = findVital(props.vitals, "HP")
	local mana = findVital(props.vitals, "MP")
	local stamina = findVital(props.vitals, "Stamina")
	-- Called unconditionally regardless of whether `stamina` currently resolves, so the hook order
	-- never depends on the stats snapshot's shape.
	local staminaRatio = useTweenedNumber(if stamina then stamina.ratio else 0)

	return e(Panel, {
		role = "AmbientPanel",
		size = UDim2.fromScale(0.88, 0.84),
		position = UDim2.fromScale(0.5, 0.5),
		anchorPoint = Vector2.new(0.5, 0.5),
		corner = false,
		stroke = true,
		-- Inset from the stroke as well as from the surface edge: the rows sat flush against the
		-- border without it.
		padding = theme.metrics.paddingMd,
	}, {
		Health = if health
			then e(VitalGauge, {
				icon = HEART_ICON,
				caption = "HP",
				vital = health,
				size = UDim2.fromScale(0.76, 0.5),
				position = UDim2.fromScale(0, 0),
			})
			else nil,
		Mana = if mana
			then e(VitalGauge, {
				icon = DROPLET_ICON,
				caption = "MP",
				vital = mana,
				size = UDim2.fromScale(0.76, 0.5),
				position = UDim2.fromScale(0, 0.5),
			})
			else nil,
		Stamina = if stamina
			then e(RadialGauge, {
				value = staminaRatio,
				label = "STAM",
				-- Sized off height, the short axis. The aspect constraint keeps it circular, so this
				-- is effectively its diameter.
				size = UDim2.fromScale(0.46, 0.46),
				position = UDim2.fromScale(1, 0.5),
				anchorPoint = Vector2.new(1, 0.5),
			})
			else nil,
	})
end

return StatusPreviewView
