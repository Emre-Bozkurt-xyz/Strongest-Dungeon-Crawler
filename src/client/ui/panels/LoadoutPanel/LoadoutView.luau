--!strict
-- The Loadout (docs/planning/progression-direction.md, "Loadout"): how the character fights. The skill
-- bar leads, since setting it up is what the panel is for; below it, read-only, what the basic attack
-- does and which passives are chosen. The skills to fill the bar with are a panel of their own beside
-- this one (LoadoutSkillsPanel).
--
-- The form and the passives are changed in the mastery trees, so here they are links into them: Shape
-- and Infusion open their tree with that node pinned, and a chosen passive is drawn as its tree draws
-- it and opens the same way.
--
-- Laid out in logical pixels at about one screen pixel each at staging (PanelRegistry gives this
-- surface `logicalWidth`). Nothing that says something is under 17 or drawn in the faint ink.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local MasteryTree = require(ReplicatedStorage.Shared.progression.MasteryTree)

local PanelShell = require(script.Parent.Parent.Parent.components.PanelShell)
local Header = require(script.Parent.Parent.Parent.components.Header)
local Brackets = require(script.Parent.Parent.Parent.components.Brackets)
local Glyph = require(script.Parent.Parent.Parent.components.Glyph)
local ThemeContext = require(script.Parent.Parent.Parent.hooks.ThemeContext)
local UISound = require(script.Parent.Parent.Parent.UISound)
local Selector = require(script.Parent.Parent.Parent.selectors.loadout)
local Node = require(script.Parent.Parent.MasteryCanvas.Node)
local Tiles = require(script.Parent.Tiles)

local e = React.createElement

-- Logical pixels.
local WIDTH = 780
local PADDING = 26
local INNER = WIDTH - 2 * PADDING
local GAP = 22
local TITLE_HEIGHT = 44
local LABEL_HEIGHT = 30
local LABEL_GAP = 10
local SLOT_SIZE = 116
local SLOT_GAP = 22
local HINT_HEIGHT = 30
local BAR_HEIGHT = SLOT_SIZE + 8 + Tiles.NAME_HEIGHT + 6 + HINT_HEIGHT
local PASSIVES_WIDTH = 236
local COLUMN_GAP = 18
local CARD_PAD = 16
local WEAPON_WIDTH = 104
local FORM_NAME_HEIGHT = 34
local ROW_HEIGHT = 30
local PASSIVE_ROW = 58

export type PassiveCell = {
	-- The chosen node, built as its tree would draw it; nil for an empty or locked slot.
	node: MasteryTree.Node?,
	trackId: string?,
	unlocksAt: number?,
}

export type Props = {
	form: Selector.FormView,
	attuned: { string },
	passives: { PassiveCell },
	sets: { Selector.SetView },
	editingSet: number,
	slots: { Selector.SlotView },
	picked: number?,
	dropSlot: number?,
	-- The display name of a skill waiting for a slot.
	heldName: string?,
	skillsShown: boolean,
	onToggleSkills: () -> (),
	onSetSelected: (set: number) -> (),
	onSlotActivated: (index: number) -> (),
	onClearPicked: () -> (),
	-- Open a mastery tree at a node, or with none the masteries' own menu.
	onOpenNode: (trackId: string?, nodeId: string?) -> (),
}

local function label(theme: any, text: string, props: { [string]: any }?)
	local base: { [string]: any } = {
		Size = UDim2.new(0.5, 0, 0, LABEL_HEIGHT),
		BackgroundTransparency = 1,
		Text = text,
		FontFace = theme.face.bodyBold,
		TextSize = 18,
		TextColor3 = theme.color.textMuted,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for key, value in pairs(props or {}) do
		base[key] = value
	end
	return e("TextLabel", base)
end

-- A headed block: its label (and whatever sits on its right), then the content.
local function Section(props: { title: string, aside: any?, height: number, layoutOrder: number?, children: any })
	local theme = ThemeContext.useTheme()
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, LABEL_HEIGHT + LABEL_GAP + props.height),
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
	}, {
		Title = label(theme, props.title),
		Aside = props.aside,
		Content = e("Frame", {
			Size = UDim2.new(1, 0, 0, props.height),
			Position = UDim2.fromOffset(0, LABEL_HEIGHT + LABEL_GAP),
			BackgroundTransparency = 1,
		}, props.children),
	})
end

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

-- A bordered text button, sized to its text.
local function OutlineButton(props: {
	text: string,
	trailing: string?,
	height: number,
	layoutOrder: number?,
	position: UDim2?,
	anchorPoint: Vector2?,
	onActivated: () -> (),
})
	local theme = ThemeContext.useTheme()
	local hovered, hoverEvents = useHover()
	return e("TextButton", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, props.height),
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		BackgroundColor3 = theme.color.backdrop,
		BackgroundTransparency = if hovered then 0.25 else 0.5,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = props.layoutOrder,
		[React.Event.MouseEnter] = hoverEvents[React.Event.MouseEnter],
		[React.Event.MouseLeave] = hoverEvents[React.Event.MouseLeave],
		[React.Event.Activated] = props.onActivated,
	}, {
		Stroke = e("UIStroke", {
			Color = if hovered then theme.color.accent else theme.color.strokeStrong,
			Thickness = 1,
			Transparency = if hovered then 0 else 0.45,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		Padding = e("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }),
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 10),
		}),
		Text = e("TextLabel", {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, props.height),
			BackgroundTransparency = 1,
			Text = props.text,
			FontFace = theme.face.bodyBold,
			TextSize = 18,
			TextColor3 = theme.color.textPrimary,
			LayoutOrder = 1,
		}),
		Trailing = if props.trailing
			then e("TextLabel", {
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, props.height),
				BackgroundTransparency = 1,
				Text = props.trailing,
				FontFace = theme.face.mono,
				TextSize = 18,
				TextColor3 = theme.color.accent,
				LayoutOrder = 2,
			})
			else nil,
	})
end

local function TitleRow(props: Props)
	local theme = ThemeContext.useTheme()
	local attunedText = if #props.attuned > 0
		then `ATTUNED  ·  <font color="#{theme.color.textPrimary:ToHex()}">{string.upper(table.concat(props.attuned, "  ·  "))}</font>`
		else "NOTHING ATTUNED"
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, TITLE_HEIGHT),
		BackgroundTransparency = 1,
		LayoutOrder = 1,
	}, {
		Header = e(Header, { title = "LOADOUT", height = 1 }),
		Right = e("Frame", {
			Size = UDim2.new(0.62, 0, 1, -8),
			Position = UDim2.fromScale(1, 0),
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 1,
		}, {
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Right,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 18),
			}),
			Attuned = e("TextLabel", {
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 32),
				BackgroundTransparency = 1,
				RichText = true,
				Text = attunedText,
				FontFace = theme.face.bodyBold,
				TextSize = 18,
				TextColor3 = theme.color.textMuted,
				LayoutOrder = 1,
			}),
			Skills = e(OutlineButton, {
				text = "SKILLS",
				trailing = if props.skillsShown then "‹" else "›",
				height = 34,
				layoutOrder = 2,
				onActivated = props.onToggleSkills,
			}),
		}),
	})
end

local function SetTabs(props: Props)
	local theme = ThemeContext.useTheme()
	local tabs: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 8),
		}),
	}
	for _, set in ipairs(props.sets) do
		local locked = set.unlocksAt ~= nil
		local on = set.index == props.editingSet
		tabs[`Set{set.index}`] = e("TextButton", {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, LABEL_HEIGHT + 2),
			BackgroundColor3 = theme.color.backdrop,
			BackgroundTransparency = if on then 0.3 else 0.65,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			LayoutOrder = set.index,
			[React.Event.Activated] = if locked or on
				then nil
				else function()
					props.onSetSelected(set.index)
				end,
		}, {
			Padding = e("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }),
			Stroke = e("UIStroke", {
				Color = theme.color.strokeStrong,
				Thickness = 1,
				Transparency = if on then 0.1 elseif locked then 0.65 else 0.45,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 8),
			}),
			Lock = if locked
				then e(Glyph, {
					glyph = "lock",
					color = theme.color.textMuted,
					size = UDim2.fromOffset(17, 17),
				})
				else nil,
			Text = e("TextLabel", {
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, LABEL_HEIGHT + 2),
				BackgroundTransparency = 1,
				Text = if locked then `SET {set.index}  ·  LV {set.unlocksAt}` else `SET {set.index}`,
				FontFace = theme.face.bodyBold,
				TextSize = 18,
				TextColor3 = if on then theme.color.textPrimary else theme.color.textMuted,
				LayoutOrder = 2,
			}),
		})
	end
	return e("Frame", {
		Size = UDim2.new(0.6, 0, 0, LABEL_HEIGHT + 2),
		Position = UDim2.new(1, 0, 0, -1),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
	}, tabs)
end

local function SlotBar(props: Props)
	local theme = ThemeContext.useTheme()
	local slots: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, SLOT_GAP),
		}),
	}
	for _, slot in ipairs(props.slots) do
		slots[`Slot{slot.index}`] = e(Tiles.Slot, {
			slot = slot,
			size = SLOT_SIZE,
			picked = props.picked == slot.index,
			target = props.dropSlot == slot.index,
			layoutOrder = slot.index,
			onActivated = function()
				props.onSlotActivated(slot.index)
			end,
		})
	end

	local white = theme.color.textPrimary:ToHex()
	local function strong(text: string): string
		return `<font color="#{white}"><b>{text}</b></font>`
	end
	local picked = props.picked and props.slots[props.picked]
	local hint = if picked
		then `Slot {strong(picked.keyLabel)} picked. Click a skill to put it here.`
		elseif props.heldName then `Holding {strong(props.heldName)}. Click a slot to put it there.`
		elseif props.skillsShown then "Drag a skill onto a slot, or click a slot and then a skill."
		else `Open {strong("SKILLS")} to choose what goes in each slot.`
	return e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
		Bar = e("Frame", {
			Size = UDim2.new(1, 0, 0, SLOT_SIZE),
			BackgroundTransparency = 1,
		}, slots),
		Hint = e("TextLabel", {
			Size = UDim2.new(1, -150, 0, HINT_HEIGHT),
			Position = UDim2.fromScale(0, 1),
			AnchorPoint = Vector2.new(0, 1),
			BackgroundTransparency = 1,
			RichText = true,
			Text = hint,
			FontFace = theme.face.body,
			TextSize = 20,
			TextColor3 = theme.color.textMuted,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}),
		Clear = if picked and picked.skill
			then e(OutlineButton, {
				text = "TAKE OUT",
				height = HINT_HEIGHT + 2,
				position = UDim2.new(1, 0, 1, 1),
				anchorPoint = Vector2.new(1, 1),
				onActivated = props.onClearPicked,
			})
			else nil,
	})
end

-- One line of the form's recipe: a key, then its value, a link into the tree when it has one.
local function RecipeRow(props: { name: string, value: string, muted: boolean?, y: number, onActivated: (() -> ())? })
	local theme = ThemeContext.useTheme()
	local hovered, hoverEvents = useHover()
	local link = props.onActivated ~= nil
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
		Position = UDim2.fromOffset(0, props.y),
		BackgroundTransparency = 1,
	}, {
		Key = e("TextLabel", {
			Size = UDim2.new(0, 106, 1, 0),
			BackgroundTransparency = 1,
			Text = props.name,
			FontFace = theme.face.bodyBold,
			TextSize = 18,
			TextColor3 = theme.color.textMuted,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Value = e(if link then "TextButton" else "TextLabel", {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, ROW_HEIGHT),
			Position = UDim2.fromOffset(110, 0),
			BackgroundTransparency = 1,
			Text = if link then `{props.value}  ↗` else props.value,
			FontFace = if props.muted then theme.face.body else theme.face.bodyBold,
			TextSize = 21,
			TextColor3 = if link and hovered
				then theme.color.accent
				elseif props.muted then theme.color.textMuted
				else theme.color.textPrimary,
			TextXAlignment = Enum.TextXAlignment.Left,
			AutoButtonColor = if link then false else nil,
			[React.Event.MouseEnter] = if link then hoverEvents[React.Event.MouseEnter] else nil,
			[React.Event.MouseLeave] = if link then hoverEvents[React.Event.MouseLeave] else nil,
			[React.Event.Activated] = props.onActivated,
		} :: any),
	})
end

local function formRows(form: Selector.FormView): number
	return 3 + (if form.infusion then 1 else 0)
end

local function formHeight(form: Selector.FormView): number
	return CARD_PAD + FORM_NAME_HEIGHT + 6 + formRows(form) * ROW_HEIGHT + 10 + ROW_HEIGHT + CARD_PAD
end

local function cardFrame(theme: any, height: number, children: any)
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = theme.color.surfaceRaised,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
	}, {
		Stroke = e("UIStroke", {
			Color = theme.color.strokeStrong,
			Thickness = 1,
			Transparency = 0.7,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		Corners = e(Brackets, { size = "small", color = theme.color.strokeStrong, edgeTransparency = 1 }),
		Body = e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, children),
	})
end

local function FormCard(props: Props & { height: number })
	local theme = ThemeContext.useTheme()
	local form = props.form
	local shapeTrack = form.shape.track
	local shapeNode = form.shape.node
	local infusion = form.infusion

	local rows: { [string]: any } = {}
	local y = 0
	local function row(name: string, value: string, muted: boolean?, onActivated: (() -> ())?)
		rows[name] = e(RecipeRow, { name = name, value = value, muted = muted, y = y, onActivated = onActivated })
		y += ROW_HEIGHT
	end
	row("SHAPE", form.shape.name, false, if shapeTrack and shapeNode
		then function()
			props.onOpenNode(shapeTrack, shapeNode)
		end
		else nil)
	row("INFUSION", if infusion then infusion.name else "None", infusion == nil, if infusion and infusion.track
		then function()
			props.onOpenNode(infusion.track, infusion.node)
		end
		else nil)
	row("COST", form.cost)
	if infusion then
		row("DAMAGE", form.damage)
	end

	-- The combo's shape: a bar per step, as long as its share of the damage.
	local strongest = 0
	for _, multiplier in ipairs(form.steps) do
		strongest = math.max(strongest, multiplier)
	end
	local bars: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for index, multiplier in ipairs(form.steps) do
		bars[`Step{index}`] = e("Frame", {
			Size = UDim2.fromOffset(math.floor(14 + 26 * multiplier / math.max(strongest, 0.01)), 8),
			BackgroundColor3 = if multiplier >= strongest then theme.color.accentTo else theme.color.textPrimary,
			BorderSizePixel = 0,
			LayoutOrder = index,
		})
	end

	local bodyX = CARD_PAD + WEAPON_WIDTH + 18
	return cardFrame(theme, props.height, {
		Weapon = e("Frame", {
			Size = UDim2.new(0, WEAPON_WIDTH, 1, -2 * CARD_PAD),
			Position = UDim2.fromOffset(CARD_PAD, CARD_PAD),
			BackgroundColor3 = theme.color.backdrop,
			BackgroundTransparency = 0.4,
			BorderSizePixel = 0,
		}, {
			Stroke = e("UIStroke", { Color = theme.color.strokeStrong, Thickness = 1, Transparency = 0.5 }),
			Glow = e("Frame", {
				Size = UDim2.fromScale(1, 0.55),
				Position = UDim2.fromScale(0, 1),
				AnchorPoint = Vector2.new(0, 1),
				BackgroundColor3 = theme.color.accent,
				BorderSizePixel = 0,
			}, {
				Fade = e("UIGradient", {
					Rotation = -90,
					Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 0.55),
						NumberSequenceKeypoint.new(1, 1),
					}),
				}),
			}),
			Glyph = e(Glyph, {
				glyph = form.weaponGlyph,
				color = theme.color.textPrimary,
				size = UDim2.fromOffset(58, 58),
				position = UDim2.fromScale(0.5, 0.4),
				anchorPoint = Vector2.new(0.5, 0.5),
			}),
			Name = e("TextLabel", {
				Size = UDim2.new(1, -8, 0, 40),
				Position = UDim2.new(0.5, 0, 1, -6),
				AnchorPoint = Vector2.new(0.5, 1),
				BackgroundTransparency = 1,
				Text = form.weaponName,
				FontFace = theme.face.bodyBold,
				TextSize = 17,
				TextWrapped = true,
				TextYAlignment = Enum.TextYAlignment.Bottom,
				TextColor3 = theme.color.textPrimary,
			}),
		}),
		Main = e("Frame", {
			Size = UDim2.new(1, -(bodyX + CARD_PAD), 1, -2 * CARD_PAD),
			Position = UDim2.fromOffset(bodyX, CARD_PAD),
			BackgroundTransparency = 1,
		}, {
			Name = e("TextLabel", {
				Size = UDim2.new(1, 0, 0, FORM_NAME_HEIGHT),
				BackgroundTransparency = 1,
				Text = string.upper(form.displayName),
				FontFace = theme.face.display,
				TextSize = 24,
				TextColor3 = theme.color.textPrimary,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}),
			Rows = e("Frame", {
				Size = UDim2.new(1, 0, 0, y),
				Position = UDim2.fromOffset(0, FORM_NAME_HEIGHT + 6),
				BackgroundTransparency = 1,
			}, rows),
			Footer = e("Frame", {
				Size = UDim2.new(1, 0, 0, ROW_HEIGHT),
				Position = UDim2.fromScale(0, 1),
				AnchorPoint = Vector2.new(0, 1),
				BackgroundTransparency = 1,
			}, {
				Combo = e("Frame", { Size = UDim2.fromScale(0.4, 1), BackgroundTransparency = 1 }, bars),
				Change = e("TextButton", {
					AutomaticSize = Enum.AutomaticSize.X,
					Size = UDim2.fromOffset(0, ROW_HEIGHT),
					Position = UDim2.fromScale(1, 0),
					AnchorPoint = Vector2.new(1, 0),
					BackgroundTransparency = 1,
					RichText = true,
					Text = `Change in Masteries  <font face="RobotoMono">[M]</font>`,
					FontFace = theme.face.bodyBold,
					TextSize = 19,
					TextColor3 = theme.color.accent,
					AutoButtonColor = false,
					[React.Event.Activated] = function()
						props.onOpenNode(shapeTrack, shapeNode)
					end,
				}),
			}),
		}),
	})
end

-- The chosen passives, drawn as their trees draw them; until a slot opens, one line saying when.
local function PassivesCard(props: Props & { height: number })
	local theme = ThemeContext.useTheme()
	local still = React.useBinding(1)
	local clock = React.useBinding(0)

	local open: { PassiveCell } = {}
	local nextLevel: number? = nil
	for _, cell in ipairs(props.passives) do
		if cell.unlocksAt then
			nextLevel = nextLevel or cell.unlocksAt
		else
			table.insert(open, cell)
		end
	end

	local children: { [string]: any } = {}
	if #open == 0 then
		children.Locked = e("Frame", {
			Size = UDim2.new(1, -2 * CARD_PAD, 1, -2 * CARD_PAD),
			Position = UDim2.fromOffset(CARD_PAD, CARD_PAD),
			BackgroundTransparency = 1,
		}, {
			Icon = e(Glyph, {
				glyph = "lock",
				color = theme.color.textMuted,
				size = UDim2.fromOffset(24, 24),
				-- Centred on the title's line, which is what it marks.
				position = UDim2.fromOffset(0, 15),
				anchorPoint = Vector2.new(0, 0.5),
			}),
			Title = e("TextLabel", {
				Size = UDim2.new(1, -38, 0, 26),
				Position = UDim2.fromOffset(38, 2),
				BackgroundTransparency = 1,
				Text = if nextLevel then `Opens at LV {nextLevel}` else "None yet",
				FontFace = theme.face.bodyBold,
				TextSize = 20,
				TextColor3 = theme.color.textPrimary,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Body = e("TextLabel", {
				Size = UDim2.new(1, -38, 0, 60),
				Position = UDim2.fromOffset(38, 36),
				BackgroundTransparency = 1,
				Text = "Passives are chosen in the mastery trees.",
				FontFace = theme.face.body,
				TextSize = 18,
				TextWrapped = true,
				TextColor3 = theme.color.textMuted,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
			}),
		})
		return cardFrame(theme, props.height, children)
	end

	for index, cell in ipairs(open) do
		local node = cell.node
		local trackId = cell.trackId
		local centre = Vector2.new(26, PASSIVE_ROW / 2)
		local mark: any
		if node and trackId then
			mark = e(Node.render, {
				node = node,
				trackId = trackId,
				position = centre,
				unseen = false,
				appear = still,
				clock = clock,
				onHover = function() end,
				onLeave = function() end,
				onActivated = function()
					props.onOpenNode(trackId, node.id)
				end,
			})
		else
			mark = e("Frame", {
				Size = UDim2.fromOffset(36, 36),
				Position = UDim2.fromOffset(centre.X, centre.Y),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
			}, {
				Round = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
				Stroke = e("UIStroke", { Color = theme.color.textMuted, Thickness = 2, Transparency = 0.2 }),
			})
		end
		children[`Row{index}`] = e("Frame", {
			Size = UDim2.new(1, -2 * CARD_PAD + 8, 0, PASSIVE_ROW),
			Position = UDim2.fromOffset(CARD_PAD - 4, CARD_PAD - 8 + (index - 1) * PASSIVE_ROW),
			BackgroundTransparency = 1,
		}, {
			Mark = mark,
			Name = e("TextLabel", {
				Size = UDim2.new(1, -62, 0, 24),
				Position = UDim2.new(0, 60, 0.5, 0),
				AnchorPoint = Vector2.new(0, 1),
				BackgroundTransparency = 1,
				Text = if node then node.displayName else "Open slot",
				FontFace = theme.face.bodyBold,
				TextSize = 20,
				TextColor3 = theme.color.textPrimary,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}),
			Detail = e("TextLabel", {
				Size = UDim2.new(1, -62, 0, 22),
				Position = UDim2.new(0, 60, 0.5, 0),
				BackgroundTransparency = 1,
				Text = if node then "In effect" else "Pick one in a tree",
				FontFace = theme.face.body,
				TextSize = 18,
				TextColor3 = theme.color.textMuted,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
		})
	end
	if nextLevel then
		children.Next = e("TextLabel", {
			Size = UDim2.new(1, -2 * CARD_PAD, 0, 22),
			Position = UDim2.new(0, CARD_PAD, 1, -CARD_PAD),
			AnchorPoint = Vector2.new(0, 1),
			BackgroundTransparency = 1,
			Text = `Next opens at LV {nextLevel}`,
			FontFace = theme.face.body,
			TextSize = 18,
			TextColor3 = theme.color.textMuted,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
	end
	return cardFrame(theme, props.height, children)
end

local function passivesHeight(passives: { PassiveCell }): number
	local open, locked = 0, false
	for _, cell in ipairs(passives) do
		if cell.unlocksAt then
			locked = true
		else
			open += 1
		end
	end
	if open == 0 then
		return 0
	end
	return CARD_PAD - 8 + open * PASSIVE_ROW + (if locked then 26 else 0) + CARD_PAD
end

local function withHeight(props: Props, height: number): any
	local out = table.clone(props) :: any
	out.height = height
	return out
end

local function LoadoutView(props: Props)
	local cardHeight = math.max(formHeight(props.form), passivesHeight(props.passives))
	local height = 2 * PADDING + TITLE_HEIGHT + GAP + (LABEL_HEIGHT + LABEL_GAP + BAR_HEIGHT) + GAP + (LABEL_HEIGHT + LABEL_GAP + cardHeight)
	local formWidth = INNER - PASSIVES_WIDTH - COLUMN_GAP

	return e(PanelShell, { padding = PADDING, gap = GAP, height = height }, {
		Title = e(TitleRow, props),
		Bar = e(Section, {
			title = "SKILL BAR",
			aside = e(SetTabs, props),
			height = BAR_HEIGHT,
			layoutOrder = 2,
		}, { Bar = e(SlotBar, props) }),
		Lower = e("Frame", {
			Size = UDim2.new(1, 0, 0, LABEL_HEIGHT + LABEL_GAP + cardHeight),
			BackgroundTransparency = 1,
			LayoutOrder = 3,
		}, {
			Form = e("Frame", { Size = UDim2.new(0, formWidth, 1, 0), BackgroundTransparency = 1 }, {
				Section = e(Section, { title = "BASIC ATTACK", height = cardHeight }, {
					Card = e(FormCard, withHeight(props, cardHeight)),
				}),
			}),
			Passives = e("Frame", {
				Size = UDim2.new(0, PASSIVES_WIDTH, 1, 0),
				Position = UDim2.fromScale(1, 0),
				AnchorPoint = Vector2.new(1, 0),
				BackgroundTransparency = 1,
			}, {
				Section = e(Section, { title = "PASSIVES", height = cardHeight }, {
					Card = e(PassivesCard, withHeight(props, cardHeight)),
				}),
			}),
		}),
	})
end

return LoadoutView
