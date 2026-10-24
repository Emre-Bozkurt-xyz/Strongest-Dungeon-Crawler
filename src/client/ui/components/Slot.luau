--!strict
-- One item slot: a dark well, corner ticks, rarity as a lit floor, an icon, a stack count, and a
-- click target.
--
-- Rarity is light rising from the slot's floor rather than a coloured box, so a full grid stays calm
-- and the rare items still catch the eye. It is passed as a key and resolved through the theme, so a
-- skin decides what each rarity looks like.
--
-- Presentational: it takes what to show and reports clicks. It does not know about inventory state,
-- which is what lets the equipment panel reuse it for sockets that hold a fixed kind of item.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ThemeContext = require(script.Parent.Parent.hooks.ThemeContext)
local useSpring = require(script.Parent.Parent.hooks.useSpring)
local Brackets = require(script.Parent.Brackets)
local Glyph = require(script.Parent.Glyph)
local UISound = require(script.Parent.Parent.UISound)

local e = React.createElement

export type Props = {
	icon: string?,
	-- An ItemGlyphs id, drawn in the rarity colour when the item has no icon.
	glyph: string?,
	-- "normal" | "magic" | "rare" | "unique", or nil for an empty slot.
	rarity: string?,
	-- Shown bottom-right when above 1.
	count: number?,
	selected: boolean?,
	-- "item" is an inventory slot. "socket" is an equipment paper-doll cut-out: dimmer, with the
	-- placeholder silhouette showing what belongs there while it is empty.
	variant: ("item" | "socket")?,
	-- Dimmed silhouette shown while the slot is empty. Empty string or nil renders nothing.
	placeholderIcon: string?,
	-- The same, as an ItemGlyphs id, for sockets that hint what belongs in them.
	placeholderGlyph: string?,
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
	local lit = hovered or props.selected == true
	local lift = useSpring(if lit then 1 else 0, theme.motion.snap)

	local socket = props.variant == "socket"
	local tint = if props.rarity then (theme.rarity :: any)[props.rarity] else nil
	local hasIcon = props.icon ~= nil and props.icon ~= ""

	local well: { [string]: any } = {
		Outline = e("UIStroke", {
			Color = if lit then theme.color.stroke else theme.color.socketStroke,
			Thickness = if props.selected then theme.metrics.strokeThick else theme.metrics.strokeThin,
			Transparency = if lit then 0 elseif socket then 0.5 else 0.35,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		Ticks = e(Brackets, {
			size = "small",
			color = if lit then theme.color.strokeStrong else theme.color.stroke,
			edgeTransparency = 1,
		}),
		Scale = e("UIScale", {
			Scale = lift:map(function(v: number)
				return 1 + 0.06 * v
			end),
		}),
	}

	if tint then
		well.Glow = e("Frame", {
			Size = UDim2.fromScale(1, 0.6),
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			BackgroundColor3 = tint,
			BorderSizePixel = 0,
		}, {
			Fade = e("UIGradient", {
				Rotation = -90,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.55),
					NumberSequenceKeypoint.new(1, 1),
				}),
			}),
		})
		well.Floor = e("Frame", {
			Size = UDim2.new(1, 0, 0, 2),
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			BackgroundColor3 = tint,
			BorderSizePixel = 0,
		})
	end

	if hasIcon then
		well.Icon = e("ImageLabel", {
			Image = props.icon,
			Size = UDim2.fromScale(0.72, 0.72),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.48),
			BackgroundTransparency = 1,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 5,
		})
	elseif tint then
		-- Stand-in until items have icons: what kind of item it is, in its rarity, so a filled slot
		-- never reads as empty.
		well.Glyph = e(Glyph, {
			glyph = props.glyph or "box",
			color = tint,
			size = UDim2.fromScale(0.62, 0.62),
			position = UDim2.fromScale(0.5, 0.47),
			zIndex = 5,
		})
	elseif props.placeholderGlyph then
		-- Path2D has no transparency, so the dim comes from the colour.
		well.Placeholder = e(Glyph, {
			glyph = props.placeholderGlyph,
			color = theme.color.textDisabled,
			size = UDim2.fromScale(0.5, 0.5),
			zIndex = 5,
		})
	elseif props.placeholderIcon and props.placeholderIcon ~= "" then
		well.Placeholder = e("ImageLabel", {
			Image = props.placeholderIcon,
			Size = UDim2.fromScale(0.58, 0.58),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			BackgroundTransparency = 1,
			ImageColor3 = theme.color.stroke,
			ImageTransparency = 0.7,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 5,
		})
	end

	if props.count and props.count > 1 then
		well.Count = e("TextLabel", {
			Text = tostring(props.count),
			Size = UDim2.fromScale(0.5, 0.3),
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -3, 1, -3),
			BackgroundTransparency = 1,
			FontFace = theme.face.mono,
			TextColor3 = theme.color.textPrimary,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 25,
		})
	end

	if props.aspectRatio then
		well.Ratio = e("UIAspectRatioConstraint", {
			AspectRatio = props.aspectRatio,
			DominantAxis = Enum.DominantAxis.Width,
		})
	end

	-- The well itself is the hit target: hover and click on any part of the slot.
	return e("TextButton", {
		Text = "",
		AutoButtonColor = false,
		Size = props.size or UDim2.fromScale(1, 1),
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		LayoutOrder = props.layoutOrder,
		BackgroundColor3 = theme.color.slotSurface,
		BackgroundTransparency = if socket then 0.5 elseif lit then 0.05 else 0.25,
		BorderSizePixel = 0,
		[React.Event.Activated] = function()
			if props.onActivated then
				UISound.play("confirm")
				props.onActivated()
			end
		end,
		[React.Event.MouseEnter] = function()
			setHovered(true)
			UISound.play("hover")
		end,
		[React.Event.MouseLeave] = function()
			setHovered(false)
		end,
	}, well)
end

return Slot
