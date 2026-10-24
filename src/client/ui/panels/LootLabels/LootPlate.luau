--!strict
-- One drop's name plate: its glyph and name in the rarity colour, a stack count, and on the selected
-- plate corner brackets and the pickup key. A hairline runs down from the plate to the drop, so a
-- plate pushed up out of a pile still points at its item.
--
-- Placement comes in as a binding the container writes every frame; nothing here re-renders to move.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local Brackets = require(script.Parent.Parent.Parent.components.Brackets)
local Glyph = require(script.Parent.Parent.Parent.components.Glyph)
local ThemeContext = require(script.Parent.Parent.Parent.hooks.ThemeContext)
local Selector = require(script.Parent.Parent.Parent.selectors.lootList)

local e = React.createElement

export type Placement = {
	-- Plate centre and the drop's own point, in screen pixels.
	plate: Vector2,
	anchor: Vector2,
	size: Vector2,
	visible: boolean,
}

export type Props = {
	row: Selector.RowView,
	pickupKey: string,
	placement: any,
	onSize: (uid: string, size: Vector2) -> (),
	onHovered: (uid: string) -> (),
	onActivated: (uid: string) -> (),
}

local HEIGHT = 28

local function LootPlate(props: Props)
	local theme = ThemeContext.useTheme()
	local row = props.row
	local tint = (theme.rarity :: any)[row.rarity] or theme.color.textPrimary
	local selected = row.selected

	local content: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		}),
		Padding = e("UIPadding", {
			PaddingLeft = UDim.new(0, 6),
			PaddingRight = UDim.new(0, 8),
		}),
		Accent = e("Frame", {
			Size = UDim2.fromOffset(2, 14),
			LayoutOrder = 1,
			BackgroundColor3 = tint,
			BorderSizePixel = 0,
		}),
		GlyphCell = e("Frame", {
			Size = UDim2.fromOffset(18, 18),
			LayoutOrder = 2,
			BackgroundTransparency = 1,
		}, {
			Glyph = e(Glyph, { glyph = row.glyph or "box", color = tint, thickness = 1.25 }),
		}),
		Name = e("TextLabel", {
			Text = row.name,
			Size = UDim2.fromOffset(0, HEIGHT),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = 3,
			BackgroundTransparency = 1,
			FontFace = theme.face.bodyBold,
			TextSize = theme.type.body,
			TextColor3 = tint,
		}),
	}
	if row.count then
		content.Count = e("TextLabel", {
			Text = `x{row.count}`,
			Size = UDim2.fromOffset(0, HEIGHT),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = 4,
			BackgroundTransparency = 1,
			FontFace = theme.face.mono,
			TextSize = theme.type.label,
			TextColor3 = theme.color.textMuted,
		})
	end
	if selected then
		content.Key = e("TextLabel", {
			Text = props.pickupKey,
			Size = UDim2.fromOffset(18, 18),
			LayoutOrder = 5,
			BackgroundColor3 = theme.color.accent,
			BackgroundTransparency = 0.85,
			BorderSizePixel = 0,
			FontFace = theme.face.mono,
			TextSize = theme.type.label,
			TextColor3 = theme.color.accent,
		}, {
			Stroke = e("UIStroke", {
				Color = theme.color.accent,
				Thickness = 1,
				Transparency = 0.3,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
		})
	end

	local placement = props.placement
	local function visible(p: Placement?): boolean
		return p ~= nil and p.visible
	end

	return e(React.Fragment, nil, {
		Leader = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = placement:map(function(p: Placement?)
				if not visible(p) then
					return UDim2.new()
				end
				local placed = p :: Placement
				return UDim2.fromOffset(placed.anchor.X, placed.plate.Y + placed.size.Y / 2)
			end),
			Size = placement:map(function(p: Placement?)
				if not visible(p) then
					return UDim2.new()
				end
				local placed = p :: Placement
				return UDim2.fromOffset(1, math.max(0, placed.anchor.Y - (placed.plate.Y + placed.size.Y / 2)))
			end),
			Visible = placement:map(visible),
			BackgroundColor3 = tint,
			BackgroundTransparency = if selected then 0.3 else 0.6,
			BorderSizePixel = 0,
			ZIndex = 1,
		}),
		Plate = e("TextButton", {
			Text = "",
			AutoButtonColor = false,
			Size = UDim2.fromOffset(0, HEIGHT),
			AutomaticSize = Enum.AutomaticSize.X,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = placement:map(function(p: Placement?)
				return if visible(p) then UDim2.fromOffset((p :: Placement).plate.X, (p :: Placement).plate.Y) else UDim2.new()
			end),
			Visible = placement:map(visible),
			BackgroundColor3 = theme.color.surface,
			BackgroundTransparency = if selected then 0.15 else 0.35,
			BorderSizePixel = 0,
			ZIndex = if selected then 3 else 2,
			[React.Change.AbsoluteSize] = function(rbx: GuiObject)
				props.onSize(row.uid, rbx.AbsoluteSize)
			end,
			[React.Event.MouseEnter] = function()
				props.onHovered(row.uid)
			end,
			[React.Event.Activated] = function()
				props.onActivated(row.uid)
			end,
		}, {
			Content = e("Frame", {
				Size = UDim2.fromOffset(0, HEIGHT),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundTransparency = 1,
			}, content),
		}),
		-- A sibling sized from the plate's measured size, not a child: a scale-sized child of an
		-- auto-sizing plate feeds back into its width and stretches it across the screen.
		Selection = if selected
			then e("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = placement:map(function(p: Placement?)
					return if visible(p) then UDim2.fromOffset((p :: Placement).plate.X, (p :: Placement).plate.Y) else UDim2.new()
				end),
				Size = placement:map(function(p: Placement?)
					return if visible(p) then UDim2.fromOffset((p :: Placement).size.X, (p :: Placement).size.Y) else UDim2.new()
				end),
				Visible = placement:map(visible),
				BackgroundTransparency = 1,
				ZIndex = 4,
			}, {
				Brackets = e(Brackets, { size = "small", color = tint, edgeTransparency = 1 }),
			})
			else nil,
	})
end

return LootPlate
