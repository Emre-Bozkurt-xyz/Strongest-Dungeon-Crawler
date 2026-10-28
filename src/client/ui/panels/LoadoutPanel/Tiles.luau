--!strict
-- The Loadout's pieces: a skill's picture, a slot of the bar, and a row of the skill list.
--
-- A slot is drawn like the HUD's skill slots (a dark well, a hairline, corner ticks, the key in the
-- corner) at the size of a menu, so the bar here reads as the bar the player fights with. A skill
-- the held weapon cannot use stays where it is, dimmed, with the reason in amber under it: sets are
-- not tied to a weapon, so the skill comes back the moment a weapon that fits it is drawn.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local ThemeContext = require(script.Parent.Parent.Parent.hooks.ThemeContext)
local Brackets = require(script.Parent.Parent.Parent.components.Brackets)
local SkillPicture = require(script.Parent.Parent.Parent.components.SkillPicture)
local UISound = require(script.Parent.Parent.Parent.UISound)
local Selector = require(script.Parent.Parent.Parent.selectors.loadout)

local e = React.createElement

local Tiles = {}

-- The System palette's warning amber: a skill that does not fit is a caution, not an error.
Tiles.WARN = Color3.fromRGB(255, 192, 77)

Tiles.Picture = SkillPicture

local function useHover(): (boolean, { [any]: any })
	local hovered, setHovered = React.useState(false)
	return hovered,
		{
			[React.Event.MouseEnter] = function()
				setHovered(true)
				UISound.play("hover")
			end,
			[React.Event.MouseLeave] = function()
				setHovered(false)
			end,
		}
end

export type SlotProps = {
	slot: Selector.SlotView,
	size: number,
	selected: boolean,
	layoutOrder: number,
	onActivated: () -> (),
}

function Tiles.Slot(props: SlotProps)
	local theme = ThemeContext.useTheme()
	local hovered, hoverEvents = useHover()
	local slot = props.slot
	local locked = slot.unlocksAt ~= nil
	local skill = slot.skill
	local lit = not locked and (props.selected or hovered)

	local children: { [string]: any } = {
		Stroke = e("UIStroke", {
			Color = if props.selected then theme.color.strokeStrong else theme.color.stroke,
			Thickness = if props.selected then 2 else 1,
			Transparency = if props.selected then 0 elseif locked then 0.82 else (if hovered then 0.4 else 0.7),
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		Key = e("TextLabel", {
			Size = UDim2.fromOffset(40, 16),
			Position = UDim2.fromOffset(6, 4),
			BackgroundTransparency = 1,
			Text = slot.keyLabel,
			FontFace = theme.face.mono,
			TextSize = 12,
			TextColor3 = if locked then theme.color.textDisabled else theme.color.textMuted,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 3,
		}),
	}
	if not locked then
		children.Ticks = e(Brackets, {
			size = "small",
			color = if lit then theme.color.strokeStrong else theme.color.stroke,
			edgeTransparency = 1,
		})
	end
	if locked then
		children.Lock = e("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = `OPENS\nLV {slot.unlocksAt}`,
			FontFace = theme.face.display,
			TextSize = 11,
			LineHeight = 1.3,
			TextColor3 = theme.color.textDisabled,
		})
	elseif skill then
		children.Picture = e(Tiles.Picture, {
			look = skill.look,
			size = math.floor(props.size * 0.56),
			color = if skill.misfit then theme.color.textDisabled else theme.color.textPrimary,
			zIndex = 2,
		})
	end
	children.Name = e("TextLabel", {
		Size = UDim2.new(1, 24, 0, 18),
		Position = UDim2.new(0.5, 0, 1, 8),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Text = if skill then skill.displayName elseif locked then "" else "Empty",
		FontFace = if skill then theme.face.bodyBold else theme.face.body,
		TextSize = 15,
		TextColor3 = if skill and skill.misfit
			then Tiles.WARN
			elseif skill then theme.color.textPrimary
			else theme.color.textDisabled,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	return e("TextButton", {
		Size = UDim2.fromOffset(props.size, props.size),
		BackgroundColor3 = theme.color.skillSlotSurface,
		BackgroundTransparency = if locked then 0.7 else (if lit then 0.15 else 0.3),
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = props.layoutOrder,
		[React.Event.MouseEnter] = hoverEvents[React.Event.MouseEnter],
		[React.Event.MouseLeave] = hoverEvents[React.Event.MouseLeave],
		[React.Event.Activated] = if locked then nil else props.onActivated,
	}, children)
end

export type RowProps = {
	skill: Selector.SkillView,
	keyLabel: string?,
	inspected: boolean,
	-- A slot is picked, so clicking puts this skill there.
	assigning: boolean,
	width: number,
	height: number,
	layoutOrder: number,
	onActivated: () -> (),
}

function Tiles.SkillRow(props: RowProps)
	local theme = ThemeContext.useTheme()
	local hovered, hoverEvents = useHover()
	local skill = props.skill
	local dim = skill.misfit ~= nil
	local lit = props.inspected or hovered
	local pictureSize = props.height - 14

	return e("TextButton", {
		Size = UDim2.fromOffset(props.width, props.height),
		BackgroundColor3 = theme.color.surfaceRaised,
		BackgroundTransparency = if lit then 0.35 else 0.6,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = props.layoutOrder,
		[React.Event.MouseEnter] = hoverEvents[React.Event.MouseEnter],
		[React.Event.MouseLeave] = hoverEvents[React.Event.MouseLeave],
		[React.Event.Activated] = props.onActivated,
	}, {
		Stroke = e("UIStroke", {
			Color = if props.inspected
				then theme.color.strokeStrong
				elseif props.assigning and hovered then theme.color.strokeStrong
				else theme.color.stroke,
			Thickness = 1,
			Transparency = if props.inspected then 0 elseif hovered then 0.45 else 0.8,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		Picture = e(Tiles.Picture, {
			look = skill.look,
			size = pictureSize,
			color = if dim then theme.color.textDisabled else theme.color.textPrimary,
			position = UDim2.new(0, 7 + pictureSize / 2, 0.5, 0),
		}),
		Name = e("TextLabel", {
			Size = UDim2.new(1, -(pictureSize + 52), 0, 20),
			Position = UDim2.fromOffset(pictureSize + 14, 6),
			BackgroundTransparency = 1,
			Text = skill.displayName,
			FontFace = theme.face.bodyBold,
			TextSize = 17,
			TextColor3 = if dim then theme.color.textMuted else theme.color.textPrimary,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),
		Subtitle = e("TextLabel", {
			Size = UDim2.new(1, -(pictureSize + 20), 0, 18),
			Position = UDim2.fromOffset(pictureSize + 14, props.height - 25),
			BackgroundTransparency = 1,
			Text = skill.subtitle,
			FontFace = theme.face.body,
			TextSize = 15,
			TextColor3 = if dim then Tiles.WARN else theme.color.textMuted,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),
		-- Which key fires it, when it sits in a slot of the set being edited.
		InSlot = if props.keyLabel
			then e("TextLabel", {
				Size = UDim2.fromOffset(28, 18),
				Position = UDim2.new(1, -8, 0, 7),
				AnchorPoint = Vector2.new(1, 0),
				BackgroundTransparency = 1,
				Text = props.keyLabel,
				FontFace = theme.face.mono,
				TextSize = 11,
				TextColor3 = theme.color.accent,
			}, {
				Stroke = e("UIStroke", {
					Color = theme.color.accent,
					Thickness = 1,
					Transparency = 0.5,
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				}),
			})
			else nil,
	})
end

return Tiles
