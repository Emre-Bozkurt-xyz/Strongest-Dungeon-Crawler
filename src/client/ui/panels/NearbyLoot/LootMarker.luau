--!strict
-- A drop as it shows while loot is collapsed: just its glyph in its rarity colour, on a small dark
-- disc so it reads against any floor. Names stay hidden until precision focus opens the loot up.
--
-- The rarest drop in range is marked out instead of named: its disc carries a ring of its rarity's
-- colour and the glyph is a size up, so a good drop in a pile is noticed without the pile becoming a
-- wall of text.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local Glyph = require(script.Parent.Parent.Parent.components.Glyph)
local ThemeContext = require(script.Parent.Parent.Parent.hooks.ThemeContext)
local Selector = require(script.Parent.Parent.Parent.selectors.lootList)

local e = React.createElement

export type Props = {
	row: Selector.RowView,
	-- The rarest rarity in range, when it is above normal.
	rarest: boolean,
	-- Screen position, or nil while off screen; a binding.
	position: any,
}

-- Pixels.
local SIZE = 22
local RAREST_SIZE = 28

local function LootMarker(props: Props)
	local theme = ThemeContext.useTheme()
	local row = props.row
	local tint = (theme.rarity :: any)[row.rarity] or theme.color.textPrimary
	local size = if props.rarest then RAREST_SIZE else SIZE

	return e("Frame", {
		Size = UDim2.fromOffset(size, size),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = props.position:map(function(p: Vector2?)
			return if p then UDim2.fromOffset(p.X, p.Y) else UDim2.new()
		end),
		Visible = props.position:map(function(p: Vector2?)
			return p ~= nil
		end),
		BackgroundColor3 = theme.color.surface,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Ring = if props.rarest
			then e("UIStroke", {
				Color = tint,
				Thickness = 1.5,
				Transparency = 0.15,
			})
			else nil,
		Glyph = e(Glyph, {
			glyph = row.glyph or "box",
			color = tint,
			thickness = 1.25,
			size = UDim2.fromScale(0.62, 0.62),
		}),
	})
end

return LootMarker
