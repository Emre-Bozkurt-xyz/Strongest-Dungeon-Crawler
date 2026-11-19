--!strict
-- Form and passives: the shape per weapon class, the infusion, and the chosen passives. Locked
-- options stay in each list, disabled, with what would open them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local CharacterTab = script.Parent.Parent
local Console = CharacterTab.Parent.Parent
local Controls = require(Console.Controls)
local EditorStore = require(CharacterTab.EditorStore)
local Parts = require(CharacterTab.Parts)

local e = React.createElement

local LABEL = 110

local function Forms(props: Parts.SectionProps)
	local editor, schema, state = props.editor, props.schema, props.state
	local forms = state.forms
	local children: { [string]: any } = {}

	for index, classKey in ipairs(schema.classKeys) do
		local class = forms.classes[classKey]
		if not class then
			continue
		end
		local path = `shapes.{classKey}`
		local choices: { string } = {}
		local labels: { [string]: string } = {}
		local disabled: { [string]: string } = {}
		for _, option in ipairs(Parts.list(class.options)) do
			table.insert(choices, option.id)
			labels[option.id] = option.name
			if option.locked then
				disabled[option.id] = option.locked
			end
		end
		local selected = EditorStore.value(editor, path, class.selected)
		children[`c{index}`] = e(Parts.Line, { layoutOrder = index }, {
			Label = e(Parts.Label, { text = `Shape ({classKey})`, width = LABEL }),
			Pick = e(Controls.Select, {
				value = if selected and selected ~= false and selected ~= "" then selected else nil,
				choices = choices,
				labels = labels,
				disabled = disabled,
				allowClear = true,
				clearLabel = `default ({class.default})`,
				placeholder = `default ({class.default})`,
				invalid = EditorStore.isInvalid(editor, path),
				fill = true,
				layoutOrder = 1,
				onPick = function(value)
					EditorStore.edit(path, value or false, { shapes = { [classKey] = value or false } }, true)
				end,
			}),
		})
	end

	local infusionChoices: { string } = {}
	local infusionLabels: { [string]: string } = {}
	local infusionLocked: { [string]: string } = {}
	for _, option in ipairs(Parts.list(forms.infusion.options)) do
		table.insert(infusionChoices, option.id)
		infusionLabels[option.id] = option.name
		if option.locked then
			infusionLocked[option.id] = option.locked
		end
	end
	local infusion = EditorStore.value(editor, "infusion", forms.infusion.selected)
	children.Infusion = e(Parts.Line, { layoutOrder = 50 }, {
		Label = e(Parts.Label, { text = "Infusion", width = LABEL }),
		Pick = e(Controls.Select, {
			value = if infusion and infusion ~= "" then infusion else nil,
			choices = infusionChoices,
			labels = infusionLabels,
			disabled = infusionLocked,
			allowClear = true,
			clearLabel = "none",
			placeholder = "none",
			invalid = EditorStore.isInvalid(editor, "infusion"),
			fill = true,
			layoutOrder = 1,
			onPick = function(value)
				EditorStore.edit("infusion", value or "", { infusion = value or "" }, true)
			end,
		}),
	})

	local passives = forms.passives
	local chosen: { string } = Parts.list(EditorStore.value(editor, "passives", passives.selected))
	local names: { [string]: string } = {}
	local passiveChoices: { string } = {}
	local passiveLocked: { [string]: string } = {}
	local full = #chosen >= passives.slots
	for _, option in ipairs(Parts.list(passives.options)) do
		names[option.id] = option.name
		if not table.find(chosen, option.id) then
			table.insert(passiveChoices, option.id)
			if option.locked then
				passiveLocked[option.id] = option.locked
			elseif full then
				passiveLocked[option.id] = if passives.nextSlotLevel
					then `no free slot (level {passives.nextSlotLevel} opens one)`
					else "no free slot"
			end
		end
	end
	local chips: { [string]: any } = {
		Layout = Controls.list(Enum.FillDirection.Horizontal, 6, { Wraps = true }),
	}
	for index, nodeId in ipairs(chosen) do
		chips[`p{index}`] = e(Controls.Chip, {
			text = `{names[nodeId] or nodeId}  ×`,
			layoutOrder = index,
			onActivated = function()
				local list = table.clone(chosen)
				table.remove(list, index)
				EditorStore.edit("passives", list, { passives = list }, true)
			end,
		})
	end
	chips.Add = e(Controls.Select, {
		value = nil,
		choices = passiveChoices,
		labels = names,
		disabled = passiveLocked,
		placeholder = "add a passive",
		width = 170,
		layoutOrder = 100,
		onPick = function(value)
			if value then
				local list = table.clone(chosen)
				table.insert(list, value)
				EditorStore.edit("passives", list, { passives = list }, true)
			end
		end,
	})
	children.Passives = e(Parts.Line, { auto = true, layoutOrder = 60 }, {
		Label = e(Parts.Label, { text = `Passives {#chosen}/{passives.slots}`, width = LABEL }),
		Chips = e("Frame", {
			Size = UDim2.fromOffset(0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = 1,
		}, Controls.mergeInto({ Flex = e("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }) }, chips)),
	})
	children.Problem = e(Parts.Problem, { message = EditorStore.errorFor(editor, { "shapes", "infusion", "passives" }), layoutOrder = 100 })

	local infusionName = if infusion and infusion ~= "" then infusionLabels[infusion] or infusion else "no infusion"
	return e(Controls.Section, {
		title = "Form and passives",
		summary = `{infusionName} · {#chosen} {if #chosen == 1 then "passive" else "passives"}`,
		open = props.open,
		onToggle = props.onToggle,
		layoutOrder = props.layoutOrder,
	}, children)
end

return Forms
