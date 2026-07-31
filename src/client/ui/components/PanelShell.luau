--!strict
-- The outer chrome menu panels share: a translucent backdrop wrapping a rounded body.
--
-- Two things vary between panels and both are props here, because assuming either one caused a
-- rebuild:
--
--   `inset`  -- the body can fill the backdrop (ItemInspect, Inventory) or float inside it as a
--              smaller card with the backdrop showing around it (SystemPanel, at 0.6 x 0.8).
--   `layout` -- "stack" gives children a vertical UIListLayout; "free" gives them none, for panels
--              that position their blocks absolutely. The Studio panels use both, and forcing the
--              stack on a composed layout collapses it into a column.
--
-- With `layout = "free"`, children set their own Position/Size/AnchorPoint in scale.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ThemeContext = require(script.Parent.Parent.hooks.ThemeContext)
local Panel = require(script.Parent.Panel)

local e = React.createElement

export type Props = {
	-- Body size within the backdrop. Defaults to filling it.
	inset: UDim2?,
	layout: ("stack" | "free")?,
	-- Space between stacked blocks. Ignored when layout is "free".
	gap: number?,
	padding: number?,
	-- Body translucency, when a panel wants to sit heavier or lighter than the default.
	transparency: number?,
	gradient: boolean?,
	children: any?,
}

local function PanelShell(props: Props)
	local theme = ThemeContext.useTheme()
	local pad = props.padding or theme.metrics.paddingLg
	local inset = props.inset
	local stacked = (props.layout or "stack") == "stack"

	local body: { [string]: any } = {}
	if stacked then
		body.Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, props.gap or theme.metrics.paddingMd),
		})
	end
	if props.children then
		for key, child in pairs(props.children) do
			body[key] = child
		end
	end

	local bodyProps: { [string]: any } = {
		role = "PanelSurface",
		padding = pad,
		size = inset or UDim2.fromScale(1, 1),
	}
	if inset then
		bodyProps.anchorPoint = Vector2.new(0.5, 0.5)
		bodyProps.position = UDim2.fromScale(0.5, 0.5)
	end
	if props.gradient ~= false then
		bodyProps.gradient = {}
	end
	if props.transparency then
		bodyProps.props = { BackgroundTransparency = props.transparency }
	end

	return e(Panel, {
		role = "PanelBackdrop",
		-- An inset body already provides the visual margin, so the backdrop does not pad again.
		padding = if inset then nil else pad,
	}, {
		Body = e(Panel, bodyProps, body),
	})
end

return PanelShell
