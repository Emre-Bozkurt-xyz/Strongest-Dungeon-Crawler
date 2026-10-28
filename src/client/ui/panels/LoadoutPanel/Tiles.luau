--!strict
-- The Loadout's pieces: a slot of the bar, and a row of the skills list beside it.
--
-- A slot is drawn like the HUD's skill slots (a dark well, a hairline, corner ticks, the key in the
-- corner) at menu size, so the bar here reads as the bar the player fights with. A skill the held
-- weapon cannot use stays where it is, dimmed, with its name in amber: sets are not tied to a
-- weapon, so the skill comes back the moment a weapon that fits it is drawn.
--
-- Sizes are logical pixels at about one screen pixel each at staging. Nothing that says something is
-- under 17 or drawn in the faint ink: on a world surface both dissolve.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local React = require(ReplicatedStorage.Packages.React)

local ThemeContext = require(script.Parent.Parent.Parent.hooks.ThemeContext)
local Brackets = require(script.Parent.Parent.Parent.components.Brackets)
local Glyph = require(script.Parent.Parent.Parent.components.Glyph)
local SkillPicture = require(script.Parent.Parent.Parent.components.SkillPicture)
local UISound = require(script.Parent.Parent.Parent.UISound)
local LoadoutDragController = require(script.Parent.Parent.Parent.controllers.LoadoutDragController)
local Selector = require(script.Parent.Parent.Parent.selectors.loadout)

local e = React.createElement

local Tiles = {}

-- The System palette's warning amber: a skill that does not fit is a caution, not an error.
Tiles.WARN = Color3.fromRGB(255, 192, 77)

-- Room under a slot for its name: one line, which a long name shrinks to fit (down to the floor)
-- rather than wrapping onto a second line every slot would have to leave room for.
Tiles.NAME_HEIGHT = 26
local NAME_SIZES = { 20, 19, 18, 17 }
-- Measured in the regular weight; the bold one runs about this much wider.
local BOLD_WIDTH = 1.08

-- The largest size on the floor-bounded scale at which `text` fits `width` on one line. Measured
-- rather than TextScaled: a size constraint is applied in canvas pixels, which ignores the surface's
-- logical-pixel UIScale and would shrink the name well under the floor.
local function nameSize(text: string, width: number): number
	for _, size in ipairs(NAME_SIZES) do
		local bounds = TextService:GetTextSize(text, size, Enum.Font.TitilliumWeb, Vector2.new(10000, 100))
		if bounds.X * BOLD_WIDTH <= width then
			return size
		end
	end
	return NAME_SIZES[#NAME_SIZES]
end

local function useHover(onChange: ((boolean) -> ())?): (boolean, { [any]: any })
	local hovered, setHovered = React.useState(false)
	return hovered,
		{
			[React.Event.MouseEnter] = function()
				setHovered(true)
				UISound.play("hover")
				if onChange then
					onChange(true)
				end
			end,
			[React.Event.MouseLeave] = function()
				setHovered(false)
				if onChange then
					onChange(false)
				end
			end,
		}
end

-- The click a press turns into, unless the press became a drag.
local function clickUnlessDragged(run: () -> ()): () -> ()
	return function()
		if not LoadoutDragController.isDragging() then
			run()
		end
	end
end

export type SlotProps = {
	slot: Selector.SlotView,
	size: number,
	picked: boolean,
	-- A drag is over this slot.
	target: boolean,
	layoutOrder: number,
	onActivated: () -> (),
}

function Tiles.Slot(props: SlotProps)
	local theme = ThemeContext.useTheme()
	local hovered, hoverEvents = useHover()
	local ref = React.useRef(nil :: GuiObject?)
	local slot = props.slot
	local locked = slot.unlocksAt ~= nil
	local skill = slot.skill
	local lit = not locked and (props.picked or props.target or hovered)

	React.useEffect(function()
		local gui = ref.current
		if locked or not gui then
			return nil
		end
		return LoadoutDragController.registerSlot(slot.index, gui)
	end, { slot.index, locked } :: { any })

	local children: { [string]: any } = {
		Stroke = e("UIStroke", {
			Color = if props.target
				then theme.color.accentTo
				elseif props.picked then theme.color.accent
				else theme.color.strokeStrong,
			Thickness = if props.target then 3 elseif props.picked then 2 else 1,
			Transparency = if props.target or props.picked then 0 elseif hovered then 0.3 elseif locked then 0.65 else 0.55,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		Key = e("TextLabel", {
			Size = UDim2.fromOffset(44, 20),
			Position = UDim2.fromOffset(8, 5),
			BackgroundTransparency = 1,
			Text = slot.keyLabel,
			FontFace = theme.face.mono,
			TextSize = 17,
			TextColor3 = theme.color.textMuted,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 3,
		}),
	}
	if not locked then
		children.Ticks = e(Brackets, {
			size = "small",
			color = if props.picked then theme.color.accent elseif lit then theme.color.textPrimary else theme.color.strokeStrong,
			edgeTransparency = 1,
		})
	end
	if locked then
		children.Lock = e("Frame", {
			Size = UDim2.fromOffset(props.size, 56),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
		}, {
			Icon = e(Glyph, {
				glyph = "lock",
				color = theme.color.textMuted,
				size = UDim2.fromOffset(26, 26),
				position = UDim2.fromScale(0.5, 0),
				anchorPoint = Vector2.new(0.5, 0),
			}),
			Level = e("TextLabel", {
				Size = UDim2.new(1, 0, 0, 22),
				Position = UDim2.fromScale(0, 1),
				AnchorPoint = Vector2.new(0, 1),
				BackgroundTransparency = 1,
				Text = `LV {slot.unlocksAt}`,
				FontFace = theme.face.bodyBold,
				TextSize = 19,
				TextColor3 = theme.color.textMuted,
			}),
		})
	elseif skill then
		children.Picture = e(SkillPicture, {
			look = skill.look,
			size = math.floor(props.size * 0.52),
			color = if skill.misfit then theme.color.textMuted else theme.color.textPrimary,
			zIndex = 2,
		})
	else
		children.Plus = e("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = "+",
			FontFace = theme.face.body,
			TextSize = 34,
			TextColor3 = theme.color.textMuted,
		})
	end
	local nameText = if skill then skill.displayName elseif locked then "Locked" else "Empty"
	children.Name = e("TextLabel", {
		Size = UDim2.new(1, 20, 0, Tiles.NAME_HEIGHT),
		Position = UDim2.new(0.5, 0, 1, 8),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Text = nameText,
		FontFace = if skill then theme.face.bodyBold else theme.face.body,
		TextSize = nameSize(nameText, props.size + 20),
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = if skill and skill.misfit
			then Tiles.WARN
			elseif skill then theme.color.textPrimary
			else theme.color.textMuted,
	})

	local skillName = if skill then skill.name else nil
	return e("TextButton", {
		Size = UDim2.fromOffset(props.size, props.size),
		BackgroundColor3 = theme.color.skillSlotSurface,
		BackgroundTransparency = if locked then 0.6 elseif lit then 0.08 else 0.2,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = props.layoutOrder,
		ref = ref,
		[React.Event.MouseEnter] = hoverEvents[React.Event.MouseEnter],
		[React.Event.MouseLeave] = hoverEvents[React.Event.MouseLeave],
		[React.Event.MouseButton1Down] = if skillName and not locked
			then function()
				LoadoutDragController.press(skillName, slot.index)
			end
			else nil,
		[React.Event.Activated] = if locked then nil else clickUnlessDragged(props.onActivated),
	}, children)
end

export type RowProps = {
	skill: Selector.SkillView,
	-- The key of the slot it sits in, in the set being edited.
	keyLabel: string?,
	held: boolean,
	width: number,
	height: number,
	layoutOrder: number,
	onActivated: () -> (),
	onHover: (hovering: boolean) -> (),
}

function Tiles.SkillRow(props: RowProps)
	local theme = ThemeContext.useTheme()
	local hovered, hoverEvents = useHover(props.onHover)
	local skill = props.skill
	local dim = skill.misfit ~= nil
	local lit = props.held or hovered
	local well = props.height - 14

	return e("TextButton", {
		Size = UDim2.fromOffset(props.width, props.height),
		BackgroundColor3 = theme.color.surfaceRaised,
		BackgroundTransparency = if lit then 0.3 else 0.55,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = props.layoutOrder,
		[React.Event.MouseEnter] = hoverEvents[React.Event.MouseEnter],
		[React.Event.MouseLeave] = hoverEvents[React.Event.MouseLeave],
		[React.Event.MouseButton1Down] = function()
			LoadoutDragController.press(skill.name, nil)
		end,
		[React.Event.Activated] = clickUnlessDragged(props.onActivated),
	}, {
		Stroke = e("UIStroke", {
			Color = if props.held then theme.color.accent else theme.color.strokeStrong,
			Thickness = if props.held then 2 else 1,
			Transparency = if props.held then 0 elseif hovered then 0.35 else 0.7,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		Well = e("Frame", {
			Size = UDim2.fromOffset(well, well),
			Position = UDim2.new(0, 7, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = theme.color.skillSlotSurface,
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
		}, {
			Picture = e(SkillPicture, {
				look = skill.look,
				size = math.floor(well * 0.72),
				color = if dim then theme.color.textMuted else theme.color.textPrimary,
			}),
		}),
		Name = e("TextLabel", {
			Size = UDim2.new(1, -(well + 72), 0, 26),
			Position = UDim2.fromOffset(well + 18, 5),
			BackgroundTransparency = 1,
			Text = skill.displayName,
			FontFace = theme.face.bodyBold,
			TextSize = 21,
			TextColor3 = if dim then theme.color.textMuted else theme.color.textPrimary,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),
		Subtitle = e("TextLabel", {
			Size = UDim2.new(1, -(well + 28), 0, 22),
			Position = UDim2.new(0, well + 18, 1, -6),
			AnchorPoint = Vector2.new(0, 1),
			BackgroundTransparency = 1,
			Text = skill.subtitle,
			FontFace = theme.face.body,
			TextSize = 18,
			TextColor3 = if dim then Tiles.WARN else theme.color.textMuted,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),
		-- Which key fires it, when it sits in a slot of the set being edited.
		InSlot = if props.keyLabel
			then e("TextLabel", {
				Size = UDim2.fromOffset(38, 24),
				Position = UDim2.new(1, -10, 0, 8),
				AnchorPoint = Vector2.new(1, 0),
				BackgroundTransparency = 1,
				Text = props.keyLabel,
				FontFace = theme.face.mono,
				TextSize = 17,
				TextColor3 = theme.color.accent,
			}, {
				Stroke = e("UIStroke", {
					Color = theme.color.accent,
					Thickness = 1,
					Transparency = 0.35,
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				}),
			})
			else nil,
	})
end

return Tiles
