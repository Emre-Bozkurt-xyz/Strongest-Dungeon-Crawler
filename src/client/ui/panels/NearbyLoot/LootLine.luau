--!strict
-- What a drop reads as, wherever it is drawn: a rarity accent, its glyph and name in the rarity
-- colour, a stack count, and while selected the pickup key. Plates and list rows both lay this out,
-- so a drop looks the same as a label and as a list entry.
--
-- Returns children for a horizontal row; the caller supplies the container and its padding.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local Glyph = require(script.Parent.Parent.Parent.components.Glyph)
local Selector = require(script.Parent.Parent.Parent.selectors.lootList)

local e = React.createElement

local LootLine = {}

-- Wheel up (positive Z) steps to the previous, nearer drop; down to the next.
function LootLine.wheelDirection(input: InputObject): number?
	if input.UserInputType ~= Enum.UserInputType.MouseWheel or input.Position.Z == 0 then
		return nil
	end
	return if input.Position.Z > 0 then -1 else 1
end

function LootLine.children(row: Selector.RowView, pickupKey: string, height: number, theme: any): { [string]: any }
	local tint = (theme.rarity :: any)[row.rarity] or theme.color.textPrimary

	local children: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
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
			Size = UDim2.fromOffset(0, height),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = 3,
			BackgroundTransparency = 1,
			FontFace = theme.face.bodyBold,
			TextSize = theme.type.body,
			TextColor3 = tint,
		}),
	}
	if row.count then
		children.Count = e("TextLabel", {
			Text = `x{row.count}`,
			Size = UDim2.fromOffset(0, height),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = 4,
			BackgroundTransparency = 1,
			FontFace = theme.face.mono,
			TextSize = theme.type.label,
			TextColor3 = theme.color.textMuted,
		})
	end
	if row.selected then
		children.Key = e("TextLabel", {
			Text = pickupKey,
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
	return children
end

return LootLine
