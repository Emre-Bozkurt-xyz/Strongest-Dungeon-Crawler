--!strict
-- One item slot: rarity-tinted square, inset icon, stack count, gloss overlay, click target.
--
-- Ported from ItemSlotTemplate in docs/ui/InventoryPanel.rbxmx. The layering is load-bearing --
-- rarity tint on the outer square, a darker inset behind the icon, and a diagonal gloss on top --
-- so a slot reads as a physical object rather than a coloured box.
--
-- Presentational: it takes what to show and reports clicks. It does not know about inventory state,
-- which is what lets the equipment panel reuse it for slots that hold a fixed kind of item.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ThemeContext = require(script.Parent.Parent.hooks.ThemeContext)

local e = React.createElement

export type Props = {
	icon: string?,
	-- Tints the slot frame. Callers map rarity to a colour; the slot has no rarity vocabulary.
	tint: Color3?,
	-- Shown bottom-right when above 1.
	count: number?,
	selected: boolean?,
	-- "item" is an inventory slot: dark, filled, light outline. "socket" is an equipment paper-doll
	-- cut-out: pale face behind a heavy dark outline, no inset or gloss.
	variant: ("item" | "socket")?,
	-- Dimmed silhouette shown while the slot is empty, hinting what belongs in it. Empty string or
	-- nil renders nothing, which is correct for sockets that accept anything.
	placeholderIcon: string?,
	layoutOrder: number?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	-- Locks the slot's shape so it cannot drift with its container. Square sockets set this to 1 and
	-- give only a width; the height follows.
	aspectRatio: number?,
	onActivated: (() -> ())?,
}

local function Slot(props: Props)
	local theme = ThemeContext.useTheme()
	local hovered, setHovered = React.useState(false)

	local socket = props.variant == "socket"
	local lit = hovered or props.selected == true
	local frame = ThemeContext.useStyle(
		if socket then (if lit then "SocketHovered" else "Socket") elseif lit then "SlotHovered" else "Slot"
	)
	local inset = ThemeContext.useStyle("SlotInset")

	local frameProps: { [string]: any } = table.clone(frame)
	frameProps.Size = props.size or UDim2.fromScale(1, 1)
	frameProps.Position = props.position
	frameProps.AnchorPoint = props.anchorPoint
	frameProps.LayoutOrder = props.layoutOrder
	if props.tint then
		frameProps.BackgroundColor3 = props.tint
	end

	local insetChildren: { [string]: any } = {
		Corner = e("UICorner", { CornerRadius = UDim.new(0, theme.metrics.radiusControl) }),
	}
	-- A socket is a cut-out in the panel, so it takes neither the darker inset nor the sheen -- both
	-- read as "something is in here" and every empty socket would look filled.
	if not socket then
		insetChildren.Gloss = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = theme.color.slotSurface,
			BorderSizePixel = 0,
			ZIndex = 10,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(0, theme.metrics.radiusControl) }),
			Gradient = e("UIGradient", {
				Rotation = -36,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.4375),
					NumberSequenceKeypoint.new(0.4159, 0.8),
					NumberSequenceKeypoint.new(1, 1),
				}),
			}),
		})
	end

	if props.icon and props.icon ~= "" then
		insetChildren.Icon = e("ImageLabel", {
			Image = props.icon,
			Size = UDim2.fromScale(0.85, 0.85),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			BackgroundTransparency = 1,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 5,
		})
	elseif props.placeholderIcon and props.placeholderIcon ~= "" then
		insetChildren.Placeholder = e("ImageLabel", {
			Image = props.placeholderIcon,
			Size = UDim2.fromScale(0.62, 0.62),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			BackgroundTransparency = 1,
			ImageColor3 = theme.color.textDisabled,
			ImageTransparency = 0.45,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 5,
		})
	end

	if props.count and props.count > 1 then
		insetChildren.Count = e("TextLabel", {
			Text = tostring(props.count),
			Size = UDim2.fromScale(0.4, 0.28),
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Font = theme.font.action,
			TextColor3 = theme.color.textPrimary,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 25,
		})
	end

	return e("Frame", frameProps, {
		Corner = e("UICorner", { CornerRadius = UDim.new(0, theme.metrics.radiusControl) }),
		Ratio = if props.aspectRatio
			then e("UIAspectRatioConstraint", {
				AspectRatio = props.aspectRatio,
				DominantAxis = Enum.DominantAxis.Width,
			})
			else nil,
		-- The socket's heavy dark outline is the shape that reads on the panel, so it stays opaque
		-- and only brightens on selection; an item slot's hairline does the opposite.
		Stroke = e("UIStroke", {
			Color = if socket
				then (if props.selected then theme.color.strokeStrong else theme.color.socketStroke)
				elseif props.selected then theme.color.strokeStrong
				else theme.color.stroke,
			Thickness = if socket
				then theme.metrics.strokePanel
				elseif props.selected then theme.metrics.strokeThick
				else theme.metrics.strokeThin,
			Transparency = if socket then 0 elseif lit then 0.2 else 0.6,
		}),
		Inset = e("Frame", (function()
			local merged: { [string]: any } = if socket then { BackgroundTransparency = 1 } else table.clone(inset)
			merged.Size = UDim2.fromScale(if socket then 1 else 0.85, if socket then 1 else 0.85)
			merged.AnchorPoint = Vector2.new(0.5, 0.5)
			merged.Position = UDim2.fromScale(0.5, 0.5)
			return merged
		end)(), insetChildren),
		-- Full-bleed hit target above the visuals so the gloss cannot swallow clicks.
		Button = e("TextButton", {
			Text = "",
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 30,
			[React.Event.Activated] = props.onActivated,
			[React.Event.MouseEnter] = function()
				setHovered(true)
			end,
			[React.Event.MouseLeave] = function()
				setHovered(false)
			end,
		}),
	})
end

return Slot
