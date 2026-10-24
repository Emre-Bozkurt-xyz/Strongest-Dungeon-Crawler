--!strict
-- The outer chrome a menu panel starts from: a PanelFrame filling the surface, or inset within it.
--
-- Two things vary between panels and both are props here, because assuming either one caused a
-- rebuild:
--
--   `inset`  -- the frame can fill the surface (ItemInspect, Inventory) or float inside it as a
--              smaller card (SystemPanel, at 0.6 x 0.8).
--   `layout` -- "stack" gives children a vertical UIListLayout; "free" gives them none, for panels
--              that position their blocks absolutely.
--
-- With `layout = "free"`, children set their own Position/Size/AnchorPoint in scale.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local PanelFrame = require(script.Parent.PanelFrame)

local e = React.createElement

export type Props = {
	-- Frame size within the surface. Defaults to filling it.
	inset: UDim2?,
	layout: ("stack" | "free")?,
	-- Space between stacked blocks. Ignored when layout is "free".
	gap: number?,
	padding: number?,
	-- Fill translucency, when a panel wants to sit heavier or lighter than the theme default.
	transparency: number?,
	children: any?,
}

local function PanelShell(props: Props)
	return e(PanelFrame, {
		size = props.inset,
		position = if props.inset then UDim2.fromScale(0.5, 0.5) else nil,
		anchorPoint = if props.inset then Vector2.new(0.5, 0.5) else nil,
		layout = props.layout,
		gap = props.gap,
		padding = props.padding,
		fillTransparency = props.transparency,
	}, props.children)
end

return PanelShell
