--!strict
-- A skill's details, or the basic attack's form, beside the Loadout: what the Loadout's side slot
-- shows, as the item inspect panel does for the bag.
--
-- Reads what to show from the menu's inspect state (source "loadout"), so nothing pushes into it.
-- Its actions are the ones that do not need a slot picked first: take the skill out of its slot, or
-- open where it comes from in the mastery trees.
--
-- `script` here IS the SkillInspectPanel module, so Parent is `panels` and Parent.Parent is `ui`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ClientSpec = require(ReplicatedStorage.Shared.skills.ClientSpec)
local MasteryTracks = require(ReplicatedStorage.Shared.progression.MasteryTracks)

local PanelShell = require(script.Parent.Parent.components.PanelShell)
local Header = require(script.Parent.Parent.components.Header)
local Button = require(script.Parent.Parent.components.Button)
local ThemeContext = require(script.Parent.Parent.hooks.ThemeContext)
local useMenuState = require(script.Parent.Parent.hooks.useMenuState)
local useHeldWhileHidden = require(script.Parent.Parent.hooks.useHeldWhileHidden)
local useCombatLoadout = require(script.Parent.Parent.hooks.useCombatLoadout)
local SkillSlots = require(script.Parent.Parent.Parent.SkillsFramework.SkillSlots)
local SkillMetadataClient = require(script.Parent.Parent.Parent.SkillsFramework.SkillMetadataClient)
local ProgressionClient = require(script.Parent.Parent.Parent.Progression.ProgressionClient)
local MasteryCanvasController = require(script.Parent.Parent.controllers.MasteryCanvasController)
local Selector = require(script.Parent.Parent.selectors.loadout)
local Tiles = require(script.Parent.LoadoutPanel.Tiles)

local e = React.createElement

local PAD = 18

local function trim(value: number): string
	local rounded = math.floor(value * 10 + 0.5) / 10
	return if rounded == math.floor(rounded) then tostring(math.floor(rounded)) else tostring(rounded)
end

type Payload = { kind: string, skill: string?, set: number? }

local function SkillInspectPanel(props: { visible: boolean? })
	local theme = ThemeContext.useTheme()
	local menu = useMenuState()
	local combat = useCombatLoadout()
	local live = if menu and menu.inspect and menu.inspect.source == "loadout" then menu.inspect.payload else nil
	-- Deselecting is what hides the panel, so it holds what it showed while it fades.
	local payload: Payload? = useHeldWhileHidden(live, props.visible)

	if not payload then
		return e(PanelShell, nil, {})
	end

	local set = payload.set or SkillSlots.getActiveSet()
	local limits = SkillSlots.limits()
	local inputs: Selector.Inputs = {
		known = {},
		slots = SkillSlots.getSet(set),
		limits = limits,
		combat = combat,
		levelOf = ProgressionClient.level,
	}

	local kindText: string
	local name: string
	local look: Selector.Look
	local warn: string? = nil
	local description = ""
	local rows: { { string } } = {}
	local actions: { { label: string, run: () -> (), primary: boolean } } = {}

	if payload.kind == "form" then
		local form = Selector.form(inputs)
		kindText = if form.combination then "FORM  ·  NAMED COMBINATION" else "FORM"
		name = form.displayName
		look = form.look
		description = form.description
		for index, multiplier in ipairs(form.steps) do
			table.insert(rows, { `STEP {index}`, `{math.floor(multiplier * 100 + 0.5)}% damage` })
		end
		table.insert(rows, { "COST", `{form.cost} / step` })
		table.insert(rows, { "DAMAGE", form.damage })
		if form.scaling then
			table.insert(rows, { "SUITS", form.scaling })
		end
		local track, node = form.shape.track, form.shape.node
		if track and node then
			table.insert(actions, {
				label = "CHANGE IN MASTERIES",
				primary = true,
				run = function()
					MasteryCanvasController.open(track, nil, node)
				end,
			})
		end
	else
		local skill = payload.skill or ""
		local view = Selector.skillView(skill, inputs, nil)
		local metadata = SkillMetadataClient.get(skill)
		local spec = ClientSpec[skill]
		local track = if spec and spec.mastery then MasteryTracks.get(spec.mastery.track) else nil
		kindText = if track then `SKILL  ·  {string.upper(track.displayName)}` else "SKILL"
		name = view.displayName
		look = view.look
		warn = view.misfit
		description = if metadata and metadata.description then metadata.description else ""
		if skill == Selector.BASIC_ATTACK then
			local form = Selector.form(inputs)
			look = form.look
			table.insert(rows, { "PLAYS", form.displayName })
			table.insert(rows, { "COST", `{form.cost} / step` })
		elseif metadata then
			if metadata.cost and metadata.cost > 0 then
				table.insert(rows, { "COST", `{trim(metadata.cost)} {metadata.costResource or ""}` })
			end
			if metadata.cooldown and metadata.cooldown > 0 then
				table.insert(rows, { "COOLDOWN", `{trim(metadata.cooldown)}s` })
			end
		end
		if track then
			table.insert(rows, { "FROM", `{track.displayName} mastery` })
		end
		if view.slot then
			local slot = view.slot
			table.insert(actions, {
				label = "TAKE OUT OF SLOT",
				primary = false,
				run = function()
					SkillSlots.clear(slot, set)
				end,
			})
		end
		if track then
			local trackId = track.id
			table.insert(actions, {
				label = "OPEN MASTERY",
				primary = false,
				run = function()
					MasteryCanvasController.open(trackId)
				end,
			})
		end
	end

	local children: { [string]: any } = {
		Kind = e("TextLabel", {
			Size = UDim2.new(1, 0, 0, 14),
			BackgroundTransparency = 1,
			Text = kindText,
			FontFace = theme.face.display,
			TextSize = 10,
			TextColor3 = theme.color.textMuted,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 1,
		}),
		-- The header sizes by scale, so it gets a fixed-height frame in this pixel-laid-out panel.
		Title = e("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = 2 }, {
			Header = e(Header, { title = string.upper(name), height = 1 }),
		}),
		Well = e("Frame", {
			Size = UDim2.new(1, 0, 0, 120),
			BackgroundColor3 = theme.color.backdrop,
			BackgroundTransparency = 0.5,
			BorderSizePixel = 0,
			LayoutOrder = 3,
		}, {
			Stroke = e("UIStroke", { Color = theme.color.stroke, Thickness = 1, Transparency = 0.75 }),
			Picture = e(Tiles.Picture, {
				look = look,
				size = 84,
				color = if warn then theme.color.textDisabled else theme.color.textPrimary,
			}),
		}),
	}
	if warn then
		children.Warn = e("TextLabel", {
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.fromScale(1, 0),
			BackgroundTransparency = 1,
			Text = `{warn}. It stays in its slot and works again with a weapon that fits.`,
			FontFace = theme.face.bodyBold,
			TextSize = 14,
			TextWrapped = true,
			TextColor3 = Tiles.WARN,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 4,
		})
	end
	if description ~= "" then
		children.Description = e("TextLabel", {
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.fromScale(1, 0),
			BackgroundTransparency = 1,
			Text = description,
			FontFace = theme.face.body,
			TextSize = 16,
			TextWrapped = true,
			TextColor3 = theme.color.textPrimary,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = 5,
		})
	end
	for index, row in ipairs(rows) do
		children[`Row{index}`] = e("Frame", {
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundTransparency = 1,
			LayoutOrder = 10 + index,
		}, {
			Key = e("TextLabel", {
				Size = UDim2.new(0, 90, 1, 0),
				BackgroundTransparency = 1,
				Text = row[1],
				FontFace = theme.face.display,
				TextSize = 9,
				TextColor3 = theme.color.textMuted,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Value = e("TextLabel", {
				Size = UDim2.new(1, -94, 1, 0),
				Position = UDim2.fromOffset(94, 0),
				BackgroundTransparency = 1,
				Text = row[2],
				FontFace = theme.face.mono,
				TextSize = 13,
				TextColor3 = theme.color.textPrimary,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
			}),
		})
	end
	for index, action in ipairs(actions) do
		children[`Action{index}`] = e(Button, {
			text = action.label,
			variant = if action.primary then "primary" else "secondary",
			size = UDim2.new(1, 0, 0, 34),
			textSize = 12,
			layoutOrder = 100 + index,
			onActivated = action.run,
		})
	end

	return e(PanelShell, { gap = 10, padding = PAD }, children)
end

return SkillInspectPanel
