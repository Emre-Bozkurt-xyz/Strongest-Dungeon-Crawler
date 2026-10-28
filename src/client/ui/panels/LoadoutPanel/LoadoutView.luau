--!strict
-- The Loadout (docs/planning/progression-direction.md, "Loadout"): how the character fights. Top to
-- bottom: the basic attack's form, the chosen passives, the skill slots, then every skill the player
-- has.
--
-- The form is shown here and changed in the mastery trees: its Shape and Infusion open the tree with
-- that node pinned. The chosen passives are drawn as the trees draw them, the same nodes in a row,
-- and open their tree the same way.
--
-- Laid out in logical pixels (PanelRegistry gives this surface `logicalWidth`).

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
local WIDTH = 860
local PADDING = 22
local INNER = WIDTH - 2 * PADDING
local GAP = 16
local TITLE_HEIGHT = 34
local LABEL_HEIGHT = 18
local LABEL_GAP = 8
local FORM_HEIGHT = 150
local PASSIVE_HEIGHT = 112
local PASSIVE_CELL = 190
local SLOT_SIZE = 88
local SLOT_GAP = 18
local SLOT_BLOCK = SLOT_SIZE + 30
local ROW_HEIGHT = 56
local ROW_GAP = 6
local COLUMN_GAP = 12
local GROUP_LABEL = 22

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
	selectedSlot: number?,
	library: { Selector.SkillGroup },
	inspected: { kind: string, skill: string? }?,
	onSetSelected: (set: number) -> (),
	onSlotActivated: (index: number) -> (),
	onSkillActivated: (skill: string) -> (),
	onFormActivated: () -> (),
	-- Open a mastery tree at a node.
	onOpenNode: (trackId: string, nodeId: string) -> (),
}

local function label(theme: any, text: string, props: { [string]: any }?)
	local base: { [string]: any } = {
		Size = UDim2.new(0.5, 0, 0, LABEL_HEIGHT),
		BackgroundTransparency = 1,
		Text = text,
		FontFace = theme.face.display,
		TextSize = 12,
		TextColor3 = theme.color.textMuted,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for key, value in pairs(props or {}) do
		base[key] = value
	end
	return e("TextLabel", base)
end

-- A headed block: a small label row (and whatever sits on its right), then the content.
local function Section(props: { title: string, aside: any?, height: number, layoutOrder: number, children: any })
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

local function aside(theme: any, text: string)
	return label(theme, text, {
		Position = UDim2.fromScale(1, 0),
		AnchorPoint = Vector2.new(1, 0),
		FontFace = theme.face.mono,
		TextSize = 12,
		TextColor3 = theme.color.textDisabled,
		TextXAlignment = Enum.TextXAlignment.Right,
	})
end

-- One half of the form's recipe, a link into its mastery tree.
local function Chip(props: { kind: string, text: string, empty: boolean, onActivated: (() -> ())?, layoutOrder: number })
	local theme = ThemeContext.useTheme()
	local hovered, setHovered = React.useState(false)
	local link = props.onActivated ~= nil
	return e("TextButton", {
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 30),
		BackgroundColor3 = theme.color.backdrop,
		BackgroundTransparency = if hovered and link then 0.3 else 0.6,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = props.layoutOrder,
		[React.Event.MouseEnter] = function()
			setHovered(true)
			if link then
				UISound.play("hover")
			end
		end,
		[React.Event.MouseLeave] = function()
			setHovered(false)
		end,
		[React.Event.Activated] = props.onActivated,
	}, {
		Stroke = e("UIStroke", {
			Color = if hovered and link then theme.color.strokeStrong else theme.color.stroke,
			Thickness = 1,
			Transparency = if hovered and link then 0 elseif props.empty then 0.8 else 0.6,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		Padding = e("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }),
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 8),
		}),
		Kind = e("TextLabel", {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 30),
			BackgroundTransparency = 1,
			Text = props.kind,
			FontFace = theme.face.display,
			TextSize = 10,
			TextColor3 = theme.color.textMuted,
			LayoutOrder = 1,
		}),
		Value = e("TextLabel", {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 30),
			BackgroundTransparency = 1,
			Text = props.text,
			FontFace = theme.face.bodyBold,
			TextSize = 15,
			TextColor3 = if props.empty then theme.color.textDisabled else theme.color.textPrimary,
			LayoutOrder = 2,
		}),
		Go = if link
			then e("TextLabel", {
				Size = UDim2.fromOffset(12, 30),
				BackgroundTransparency = 1,
				Text = "↗",
				FontFace = theme.face.mono,
				TextSize = 13,
				TextColor3 = theme.color.accent,
				LayoutOrder = 3,
			})
			else nil,
	})
end

local function FormCard(props: Props)
	local theme = ThemeContext.useTheme()
	local hovered, setHovered = React.useState(false)
	local form = props.form
	local inspected = props.inspected ~= nil and props.inspected.kind == "form"
	local lit = hovered or inspected

	local shapeTrack = form.shape.track
	local shapeNode = form.shape.node
	local infusion = form.infusion

	local stats: { { string } } = {
		{ "COST", `{form.cost} / step` },
		{ "DAMAGE", form.damage },
	}
	if form.scaling then
		table.insert(stats, { "SUITS", form.scaling })
	end
	local statRows: { [string]: any } = {}
	for index, stat in ipairs(stats) do
		statRows[`Stat{index}`] = e("Frame", {
			Size = UDim2.new(1, 0, 0, 24),
			Position = UDim2.fromOffset(0, (index - 1) * 26),
			BackgroundTransparency = 1,
		}, {
			Key = label(theme, stat[1], { Size = UDim2.new(0, 70, 1, 0), TextSize = 10 }),
			Value = e("TextLabel", {
				Size = UDim2.new(1, -74, 1, 0),
				Position = UDim2.fromOffset(74, 0),
				BackgroundTransparency = 1,
				Text = stat[2],
				FontFace = theme.face.body,
				TextSize = 17,
				TextColor3 = theme.color.textPrimary,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}),
		})
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
			Padding = UDim.new(0, 5),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for index, multiplier in ipairs(form.steps) do
		bars[`Step{index}`] = e("Frame", {
			Size = UDim2.fromOffset(math.floor(12 + 26 * multiplier / math.max(strongest, 0.01)), 6),
			BackgroundColor3 = if multiplier >= strongest then theme.color.accentTo else theme.color.textPrimary,
			BorderSizePixel = 0,
			LayoutOrder = index,
		})
	end
	statRows.Combo = e("Frame", {
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.fromOffset(0, #stats * 26),
		BackgroundTransparency = 1,
	}, {
		Key = label(theme, "COMBO", { Size = UDim2.new(0, 70, 1, 0), TextSize = 10 }),
		Bars = e("Frame", {
			Size = UDim2.new(1, -74, 1, 0),
			Position = UDim2.fromOffset(74, 0),
			BackgroundTransparency = 1,
		}, bars),
	})

	return e("TextButton", {
		Size = UDim2.new(1, 0, 0, FORM_HEIGHT),
		BackgroundColor3 = theme.color.surfaceRaised,
		BackgroundTransparency = if lit then 0.35 else 0.55,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		[React.Event.MouseEnter] = function()
			setHovered(true)
		end,
		[React.Event.MouseLeave] = function()
			setHovered(false)
		end,
		[React.Event.Activated] = props.onFormActivated,
	}, {
		Stroke = e("UIStroke", {
			Color = if inspected then theme.color.strokeStrong else theme.color.stroke,
			Thickness = 1,
			Transparency = if inspected then 0 elseif hovered then 0.45 else 0.75,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		Corners = e(Brackets, { size = "small", color = if lit then theme.color.strokeStrong else theme.color.stroke, edgeTransparency = 1 }),

		Weapon = e("Frame", {
			Size = UDim2.fromOffset(104, FORM_HEIGHT - 22),
			Position = UDim2.fromOffset(11, 11),
			BackgroundColor3 = theme.color.backdrop,
			BackgroundTransparency = 0.4,
			BorderSizePixel = 0,
		}, {
			Stroke = e("UIStroke", { Color = theme.color.stroke, Thickness = 1, Transparency = 0.6 }),
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
				size = UDim2.fromOffset(56, 56),
				position = UDim2.fromScale(0.5, 0.42),
				anchorPoint = Vector2.new(0.5, 0.5),
			}),
			Name = e("TextLabel", {
				Size = UDim2.new(1, -8, 0, 32),
				Position = UDim2.new(0.5, 0, 1, -4),
				AnchorPoint = Vector2.new(0.5, 1),
				BackgroundTransparency = 1,
				Text = form.weaponName,
				FontFace = theme.face.bodyBold,
				TextSize = 13,
				TextWrapped = true,
				TextColor3 = theme.color.textPrimary,
			}),
		}),

		Main = e("Frame", {
			Size = UDim2.new(1, -(136 + 330), 1, -22),
			Position = UDim2.fromOffset(136, 11),
			BackgroundTransparency = 1,
		}, {
			Kind = label(theme, if form.combination then "FORM  ·  NAMED COMBINATION" else "FORM", {
				Size = UDim2.new(1, 0, 0, 14),
				TextSize = 9,
			}),
			Name = e("TextLabel", {
				Size = UDim2.new(1, 0, 0, 30),
				Position = UDim2.fromOffset(0, 18),
				BackgroundTransparency = 1,
				Text = string.upper(form.displayName),
				FontFace = theme.face.display,
				TextSize = 21,
				TextColor3 = theme.color.textPrimary,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}),
			Recipe = e("Frame", {
				Size = UDim2.new(1, 0, 0, 30),
				Position = UDim2.fromOffset(0, 58),
				BackgroundTransparency = 1,
			}, {
				Layout = e("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 8),
				}),
				Shape = e(Chip, {
					kind = "SHAPE",
					text = form.shape.name,
					empty = false,
					layoutOrder = 1,
					onActivated = if shapeTrack and shapeNode
						then function()
							props.onOpenNode(shapeTrack, shapeNode)
						end
						else nil,
				}),
				Infusion = e(Chip, {
					kind = "INFUSION",
					text = if infusion then infusion.name else "None",
					empty = infusion == nil,
					layoutOrder = 2,
					onActivated = if infusion and infusion.track
						then function()
							props.onOpenNode(infusion.track :: string, infusion.node)
						end
						else nil,
				}),
			}),
			Note = e("TextLabel", {
				Size = UDim2.new(1, 0, 0, 18),
				Position = UDim2.new(0, 0, 1, 0),
				AnchorPoint = Vector2.new(0, 1),
				BackgroundTransparency = 1,
				Text = "Forms and infusions are chosen in the mastery trees  [M]",
				FontFace = theme.face.body,
				TextSize = 15,
				TextColor3 = theme.color.textDisabled,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
		}),

		Stats = e("Frame", {
			Size = UDim2.new(0, 312, 1, -26),
			Position = UDim2.new(1, -12, 0, 13),
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 1,
		}, {
			Rule = e("Frame", {
				Size = UDim2.new(0, 1, 1, 0),
				Position = UDim2.fromOffset(-14, 0),
				BackgroundColor3 = theme.color.stroke,
				BackgroundTransparency = 0.85,
				BorderSizePixel = 0,
			}),
			Rows = e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, statRows),
		}),
	})
end

-- The chosen passives, drawn as their trees draw them.
local function Passives(props: Props)
	local theme = ThemeContext.useTheme()
	local still = React.useBinding(1)
	local clock = React.useBinding(0)
	local cells: { [string]: any } = {}
	for index, cell in ipairs(props.passives) do
		local centre = Vector2.new(PASSIVE_CELL / 2, 40)
		local content: any
		local node = cell.node
		local trackId = cell.trackId
		if node and trackId then
			content = e(Node.render, {
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
			-- An empty slot is the node's outline with nothing in it; a locked one is fainter still.
			content = e("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
			}, {
				Ring = e("Frame", {
					Size = UDim2.fromOffset(Node.RADIUS.select * 2, Node.RADIUS.select * 2),
					Position = UDim2.fromOffset(centre.X, centre.Y),
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundTransparency = 1,
				}, {
					Round = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
					Stroke = e("UIStroke", {
						Color = theme.color.stroke,
						Thickness = 1,
						Transparency = if cell.unlocksAt then 0.85 else 0.6,
					}),
				}),
				Text = e("TextLabel", {
					Size = UDim2.fromOffset(PASSIVE_CELL, 16),
					Position = UDim2.fromOffset(0, centre.Y + Node.reachOf("select") + 8),
					BackgroundTransparency = 1,
					Text = if cell.unlocksAt then `OPENS AT LV {cell.unlocksAt}` else "OPEN SLOT",
					FontFace = theme.face.display,
					TextSize = 11,
					TextColor3 = theme.color.textDisabled,
				}),
			})
		end
		cells[`Cell{index}`] = e("Frame", {
			Size = UDim2.fromOffset(PASSIVE_CELL, PASSIVE_HEIGHT),
			BackgroundTransparency = 1,
			LayoutOrder = index,
		}, { Content = content })
	end
	cells.Layout = e("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
	})
	return e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, cells)
end

local function SetTabs(props: Props)
	local theme = ThemeContext.useTheme()
	local tabs: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		}),
	}
	for _, set in ipairs(props.sets) do
		local locked = set.unlocksAt ~= nil
		local on = set.index == props.editingSet
		tabs[`Set{set.index}`] = e("TextButton", {
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, LABEL_HEIGHT + 4),
			BackgroundColor3 = theme.color.backdrop,
			BackgroundTransparency = if on then 0.3 else 0.7,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = if locked then `SET {set.index}  ·  LV {set.unlocksAt}` else `SET {set.index}`,
			FontFace = theme.face.display,
			TextSize = 10,
			TextColor3 = if locked then theme.color.textDisabled elseif on then theme.color.textPrimary else theme.color.textMuted,
			LayoutOrder = set.index,
			[React.Event.Activated] = if locked
				then nil
				else function()
					props.onSetSelected(set.index)
				end,
		}, {
			Padding = e("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }),
			Stroke = e("UIStroke", {
				Color = if on then theme.color.strokeStrong else theme.color.stroke,
				Thickness = 1,
				Transparency = if on then 0.2 elseif locked then 0.85 else 0.6,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
		})
	end
	return e("Frame", {
		Size = UDim2.new(0.6, 0, 0, LABEL_HEIGHT + 4),
		Position = UDim2.new(1, 0, 0, -3),
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
			selected = props.selectedSlot == slot.index,
			layoutOrder = slot.index,
			onActivated = function()
				props.onSlotActivated(slot.index)
			end,
		})
	end
	local barWidth = #props.slots * SLOT_SIZE + (#props.slots - 1) * SLOT_GAP
	local selected = props.selectedSlot and props.slots[props.selectedSlot]
	local hint = if selected
		then `Slot {selected.keyLabel} is picked. Choose a skill below to put it there, or click the slot again to let go.`
		else "Pick a slot, then a skill to put in it."
	return e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
		Bar = e("Frame", { Size = UDim2.fromOffset(barWidth, SLOT_SIZE), BackgroundTransparency = 1 }, slots),
		Hint = e("TextLabel", {
			Size = UDim2.new(1, -(barWidth + 30), 0, SLOT_SIZE),
			Position = UDim2.fromOffset(barWidth + 30, 0),
			BackgroundTransparency = 1,
			Text = hint,
			FontFace = theme.face.body,
			TextSize = 15,
			TextWrapped = true,
			TextColor3 = if selected then theme.color.textPrimary else theme.color.textMuted,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
	})
end

local function libraryHeight(groups: { Selector.SkillGroup }): number
	local rows = 0
	for _, group in ipairs(groups) do
		rows = math.max(rows, #group.skills)
	end
	return GROUP_LABEL + math.max(rows, 1) * (ROW_HEIGHT + ROW_GAP)
end

local function Library(props: Props)
	local theme = ThemeContext.useTheme()
	local columns = math.max(4, #props.library)
	local width = math.floor((INNER - (columns - 1) * COLUMN_GAP) / columns)
	local keyOf: { [string]: string } = {}
	for _, slot in ipairs(props.slots) do
		if slot.skill then
			keyOf[slot.skill.name] = slot.keyLabel
		end
	end
	local groups: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, COLUMN_GAP),
		}),
	}
	for order, group in ipairs(props.library) do
		local rows: { [string]: any } = {
			Layout = e("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, ROW_GAP) }),
		}
		for index, skill in ipairs(group.skills) do
			rows[skill.name] = e(Tiles.SkillRow, {
				skill = skill,
				keyLabel = keyOf[skill.name],
				inspected = props.inspected ~= nil and props.inspected.skill == skill.name,
				assigning = props.selectedSlot ~= nil,
				width = width,
				height = ROW_HEIGHT,
				layoutOrder = index,
				onActivated = function()
					props.onSkillActivated(skill.name)
				end,
			})
		end
		groups[group.id] = e("Frame", {
			Size = UDim2.new(0, width, 1, 0),
			BackgroundTransparency = 1,
			LayoutOrder = order,
		}, {
			Label = label(theme, group.label, { Size = UDim2.new(1, 0, 0, GROUP_LABEL - 6) }),
			Level = if group.level
				then label(theme, `LV {group.level}`, {
					Size = UDim2.new(1, 0, 0, GROUP_LABEL - 6),
					FontFace = theme.face.mono,
					TextColor3 = theme.color.textDisabled,
					TextXAlignment = Enum.TextXAlignment.Right,
				})
				else nil,
			Rows = e("Frame", {
				Size = UDim2.new(1, 0, 1, -GROUP_LABEL),
				Position = UDim2.fromOffset(0, GROUP_LABEL),
				BackgroundTransparency = 1,
			}, rows),
		})
	end
	return e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, groups)
end

local function LoadoutView(props: Props)
	local theme = ThemeContext.useTheme()

	local known = 0
	for _, group in ipairs(props.library) do
		known += #group.skills
	end
	local chosen = 0
	for _, cell in ipairs(props.passives) do
		if cell.node then
			chosen += 1
		end
	end
	local open = 0
	for _, cell in ipairs(props.passives) do
		if not cell.unlocksAt then
			open += 1
		end
	end

	local sections = {
		{ TITLE_HEIGHT },
		{ LABEL_HEIGHT + LABEL_GAP + FORM_HEIGHT },
		{ LABEL_HEIGHT + LABEL_GAP + PASSIVE_HEIGHT },
		{ LABEL_HEIGHT + LABEL_GAP + SLOT_BLOCK },
		{ LABEL_HEIGHT + LABEL_GAP + libraryHeight(props.library) },
	}
	local height = 2 * PADDING + (#sections - 1) * GAP
	for _, section in ipairs(sections) do
		height += section[1]
	end

	local attunedText = if #props.attuned > 0
		then `ATTUNED  ·  {string.upper(table.concat(props.attuned, "  ·  "))}`
		else "NOTHING ATTUNED"
	local basicSlot = props.form.slot and props.slots[props.form.slot]

	return e(PanelShell, { padding = PADDING, gap = GAP, height = height }, {
		Title = e("Frame", {
			Size = UDim2.new(1, 0, 0, TITLE_HEIGHT),
			BackgroundTransparency = 1,
			LayoutOrder = 1,
		}, {
			Header = e(Header, { title = "LOADOUT", height = 1 }),
			Attuned = label(theme, attunedText, {
				Size = UDim2.new(0.5, 0, 1, 0),
				Position = UDim2.fromScale(1, 0),
				AnchorPoint = Vector2.new(1, 0),
				TextSize = 11,
				TextColor3 = if #props.attuned > 0 then theme.color.textPrimary else theme.color.textDisabled,
				TextXAlignment = Enum.TextXAlignment.Right,
			}),
		}),
		Form = e(Section, {
			title = "WEAPON  ·  BASIC ATTACK",
			aside = aside(theme, if basicSlot then `IN SLOT {basicSlot.keyLabel}` else "NOT IN A SLOT"),
			height = FORM_HEIGHT,
			layoutOrder = 2,
		}, { Card = e(FormCard, props) }),
		Passives = e(Section, {
			title = "CHOSEN PASSIVES",
			aside = aside(theme, `{chosen} / {open}`),
			height = PASSIVE_HEIGHT,
			layoutOrder = 3,
		}, { Row = e(Passives, props) }),
		Slots = e(Section, {
			title = "SKILL SLOTS",
			aside = e(SetTabs, props),
			height = SLOT_BLOCK,
			layoutOrder = 4,
		}, { Bar = e(SlotBar, props) }),
		Skills = e(Section, {
			title = "SKILLS",
			aside = aside(theme, `{known} KNOWN`),
			height = libraryHeight(props.library),
			layoutOrder = 5,
		}, { List = e(Library, props) }),
	})
end

return LoadoutView
