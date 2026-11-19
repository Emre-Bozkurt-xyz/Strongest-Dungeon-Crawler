--!strict
-- Attributes: a stepper per attribute and for the unspent points, each typed exactly as well.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local CharacterTab = script.Parent.Parent
local Controls = require(CharacterTab.Parent.Parent.Controls)
local EditorStore = require(CharacterTab.EditorStore)
local Parts = require(CharacterTab.Parts)

local e = React.createElement

local function Attributes(props: Parts.SectionProps)
	local editor, schema, state = props.editor, props.schema, props.state
	local children: { [string]: any } = {}

	local function line(key: string, label: string, current: number, max: number?, order: number)
		local path = `attributes.{key}`
		children[key] = e(Parts.Line, { layoutOrder = order }, {
			Label = e(Parts.Label, { text = label }),
			Stepper = e(Controls.Stepper, {
				value = EditorStore.value(editor, path, current),
				min = schema.attributes.min,
				max = max,
				width = 64,
				invalid = EditorStore.isInvalid(editor, path),
				layoutOrder = 1,
				onChange = function(value)
					EditorStore.edit(path, value, { attributes = { [key] = value } })
				end,
			}),
		})
	end

	for index, name in ipairs(schema.attributes.names) do
		line(name, name, state.attributes[name] or 0, schema.attributes.max, index)
	end
	local unspent = EditorStore.value(editor, "attributes.unspent", state.unspent or 0)
	line("unspent", "Unspent", state.unspent or 0, nil, 100)
	children.Problem = e(Parts.Problem, { message = EditorStore.errorFor(editor, { "attributes" }), layoutOrder = 200 })

	return e(Controls.Section, {
		title = "Attributes",
		summary = `{unspent} unspent`,
		open = props.open,
		onToggle = props.onToggle,
		layoutOrder = props.layoutOrder,
	}, children)
end

return Attributes
