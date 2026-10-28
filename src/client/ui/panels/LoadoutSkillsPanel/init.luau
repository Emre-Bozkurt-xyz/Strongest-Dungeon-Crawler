--!strict
-- The skills to fill the Loadout's bar with, beside it in the Loadout's side slot: every skill the
-- player has, grouped by the mastery it comes from, with the slot key on any already in the bar.
--
-- Open whenever the Loadout is, until the player hides it from the Loadout's title row (a context
-- panel in the menu state, so the stage makes room for it). A skill goes into the bar by dragging it
-- onto a slot, or by clicking it and a slot in either order (LoadoutEditController). The footer
-- describes the skill under the pointer, or the last one chosen, so the Loadout needs no separate
-- inspect panel.
--
-- `script` here IS the LoadoutSkillsPanel module, so Parent is `panels` and Parent.Parent is `ui`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local PanelShell = require(script.Parent.Parent.components.PanelShell)
local Header = require(script.Parent.Parent.components.Header)
local ThemeContext = require(script.Parent.Parent.hooks.ThemeContext)
local SkillMetadataClient = require(script.Parent.Parent.Parent.SkillsFramework.SkillMetadataClient)
local LoadoutEditController = require(script.Parent.Parent.controllers.LoadoutEditController)
local Selector = require(script.Parent.Parent.selectors.loadout)
local Tiles = require(script.Parent.LoadoutPanel.Tiles)
local useLoadoutInputs = require(script.Parent.LoadoutPanel.useLoadoutInputs)

local e = React.createElement

-- Logical pixels.
local WIDTH = 400
local PADDING = 20
local INNER = WIDTH - 2 * PADDING
local GAP = 14
local TITLE_HEIGHT = 40
local GROUP_LABEL = 28
local ROW_HEIGHT = 62
local ROW_GAP = 6
local GROUP_GAP = 12
-- The list scrolls past this (about five rows), so the panel stays about as tall as the Loadout.
local LIST_MAX = 400
local SCROLLBAR = 6
local DETAIL_HEIGHT = 140

local function trim(value: number): string
	local rounded = math.floor(value * 10 + 0.5) / 10
	return if rounded == math.floor(rounded) then tostring(math.floor(rounded)) else tostring(rounded)
end

local function listHeight(groups: { Selector.SkillGroup }): number
	local height = 0
	for index, group in ipairs(groups) do
		local rows = #group.skills
		height += GROUP_LABEL + 8 + rows * ROW_HEIGHT + math.max(rows - 1, 0) * ROW_GAP
		if index > 1 then
			height += GROUP_GAP
		end
	end
	return height
end

local function Group(props: {
	group: Selector.SkillGroup,
	keyOf: { [string]: string },
	held: string?,
	width: number,
	layoutOrder: number,
})
	local theme = ThemeContext.useTheme()
	local group = props.group
	local rows: { [string]: any } = {
		Layout = e("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, ROW_GAP) }),
	}
	for index, skill in ipairs(group.skills) do
		local name = skill.name
		rows[name] = e(Tiles.SkillRow, {
			skill = skill,
			keyLabel = props.keyOf[name],
			held = props.held == name,
			width = props.width,
			height = ROW_HEIGHT,
			layoutOrder = index,
			onActivated = function()
				LoadoutEditController.activateSkill(name)
			end,
			onHover = function(hovering: boolean)
				if hovering then
					LoadoutEditController.setHovered(name)
				elseif LoadoutEditController.get().hovered == name then
					LoadoutEditController.setHovered(nil)
				end
			end,
		})
	end
	local count = #group.skills
	return e("Frame", {
		Size = UDim2.fromOffset(props.width, GROUP_LABEL + 8 + count * ROW_HEIGHT + math.max(count - 1, 0) * ROW_GAP),
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
	}, {
		Label = e("TextLabel", {
			Size = UDim2.new(1, 0, 0, GROUP_LABEL),
			BackgroundTransparency = 1,
			Text = group.label,
			FontFace = theme.face.bodyBold,
			TextSize = 18,
			TextColor3 = theme.color.textMuted,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Level = if group.level
			then e("TextLabel", {
				Size = UDim2.new(1, 0, 0, GROUP_LABEL),
				BackgroundTransparency = 1,
				Text = `LV {group.level}`,
				FontFace = theme.face.mono,
				TextSize = 17,
				TextColor3 = theme.color.textMuted,
				TextXAlignment = Enum.TextXAlignment.Right,
			})
			else nil,
		Rows = e("Frame", {
			Size = UDim2.new(1, 0, 1, -(GROUP_LABEL + 8)),
			Position = UDim2.fromOffset(0, GROUP_LABEL + 8),
			BackgroundTransparency = 1,
		}, rows),
	})
end

-- What the skill does and costs, for the one under the pointer or the last one chosen.
local function Detail(props: { skill: Selector.SkillView?, form: Selector.FormView })
	local theme = ThemeContext.useTheme()
	local skill = props.skill
	if not skill then
		return e("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = "Point at a skill to read what it does.",
			FontFace = theme.face.body,
			TextSize = 19,
			TextColor3 = theme.color.textMuted,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
		})
	end

	local metadata = SkillMetadataClient.get(skill.name)
	local basic = skill.name == Selector.BASIC_ATTACK
	local description = if metadata and metadata.description then metadata.description else ""
	local parts: { string } = {}
	local white = theme.color.textPrimary:ToHex()
	local function stat(key: string, value: string)
		table.insert(parts, `{key}  <font color="#{white}">{value}</font>`)
	end
	if basic then
		stat("Form", props.form.displayName)
		stat("Cost", props.form.cost)
	else
		if metadata and metadata.cost and metadata.cost > 0 then
			stat("Cost", `{trim(metadata.cost)} {metadata.costResource or ""}`)
		end
		if metadata and metadata.cooldown and metadata.cooldown > 0 then
			stat("Cooldown", `{trim(metadata.cooldown)}s`)
		end
	end

	local y = 0
	local children: { [string]: any } = {}
	children.Name = e("TextLabel", {
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		Text = skill.displayName,
		FontFace = theme.face.bodyBold,
		TextSize = 22,
		TextColor3 = theme.color.textPrimary,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	y += 32
	if skill.misfit then
		children.Misfit = e("TextLabel", {
			Size = UDim2.new(1, 0, 0, 22),
			Position = UDim2.fromOffset(0, y),
			BackgroundTransparency = 1,
			Text = skill.misfit,
			FontFace = theme.face.bodyBold,
			TextSize = 19,
			TextColor3 = Tiles.WARN,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		y += 26
	end
	children.Description = e("TextLabel", {
		Size = UDim2.new(1, 0, 1, -(y + 30)),
		Position = UDim2.fromOffset(0, y),
		BackgroundTransparency = 1,
		Text = description,
		FontFace = theme.face.body,
		TextSize = 19,
		TextWrapped = true,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextColor3 = theme.color.textPrimary,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	children.Stats = e("TextLabel", {
		Size = UDim2.new(1, 0, 0, 26),
		Position = UDim2.fromScale(0, 1),
		AnchorPoint = Vector2.new(0, 1),
		BackgroundTransparency = 1,
		RichText = true,
		Text = table.concat(parts, "     "),
		FontFace = theme.face.body,
		TextSize = 19,
		TextColor3 = theme.color.textMuted,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	return e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, children)
end

local function LoadoutSkillsPanel()
	local theme = ThemeContext.useTheme()
	local edit = LoadoutEditController.use()
	local inputs = useLoadoutInputs(edit.editingSet)
	local groups = Selector.library(inputs)

	local keyOf: { [string]: string } = {}
	local byName: { [string]: Selector.SkillView } = {}
	local known = 0
	for _, slot in ipairs(Selector.slots(inputs)) do
		if slot.skill then
			keyOf[slot.skill.name] = slot.keyLabel
		end
	end
	for _, group in ipairs(groups) do
		for _, skill in ipairs(group.skills) do
			byName[skill.name] = skill
			known += 1
		end
	end

	local content = listHeight(groups)
	local list = math.min(content, LIST_MAX)
	local scrolls = content > LIST_MAX
	local rowWidth = if scrolls then INNER - SCROLLBAR - 8 else INNER

	local groupChildren: { [string]: any } = {
		Layout = e("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, GROUP_GAP) }),
	}
	for order, group in ipairs(groups) do
		groupChildren[group.id] = e(Group, {
			group = group,
			keyOf = keyOf,
			held = edit.held,
			width = rowWidth,
			layoutOrder = order,
		})
	end

	local shownName = edit.hovered or edit.held or edit.shown
	local height = 2 * PADDING + TITLE_HEIGHT + GAP + list + GAP + DETAIL_HEIGHT

	return e(PanelShell, { padding = PADDING, gap = GAP, height = height }, {
		Title = e("Frame", {
			Size = UDim2.new(1, 0, 0, TITLE_HEIGHT),
			BackgroundTransparency = 1,
			LayoutOrder = 1,
		}, {
			Header = e(Header, { title = "SKILLS", height = 1 }),
			Count = e("TextLabel", {
				Size = UDim2.new(0.5, 0, 1, -8),
				Position = UDim2.fromScale(1, 0),
				AnchorPoint = Vector2.new(1, 0),
				BackgroundTransparency = 1,
				Text = `{known} known`,
				FontFace = theme.face.bodyBold,
				TextSize = 18,
				TextColor3 = theme.color.textMuted,
				TextXAlignment = Enum.TextXAlignment.Right,
			}),
		}),
		List = e("ScrollingFrame", {
			Size = UDim2.new(1, 0, 0, list),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			CanvasSize = UDim2.fromOffset(0, content),
			ScrollingDirection = Enum.ScrollingDirection.Y,
			ScrollingEnabled = scrolls,
			ScrollBarThickness = if scrolls then SCROLLBAR else 0,
			ScrollBarImageColor3 = theme.color.strokeStrong,
			ScrollBarImageTransparency = 0.4,
			LayoutOrder = 2,
		}, groupChildren),
		Detail = e("Frame", {
			Size = UDim2.new(1, 0, 0, DETAIL_HEIGHT),
			BackgroundTransparency = 1,
			LayoutOrder = 3,
		}, {
			Rule = e("Frame", {
				Size = UDim2.new(1, 0, 0, 1),
				BackgroundColor3 = theme.color.strokeStrong,
				BackgroundTransparency = 0.7,
				BorderSizePixel = 0,
			}),
			Body = e("Frame", {
				Size = UDim2.new(1, 0, 1, -14),
				Position = UDim2.fromOffset(0, 14),
				BackgroundTransparency = 1,
			}, {
				Detail = e(Detail, {
					skill = if shownName then byName[shownName] else nil,
					form = Selector.form(inputs),
				}),
			}),
		}),
	})
end

return LoadoutSkillsPanel
