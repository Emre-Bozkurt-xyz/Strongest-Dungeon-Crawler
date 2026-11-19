--!strict
-- Base stat overrides: each overridden stat with its value and remove, and a search to add one
-- (starting from the stat's default base).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local CharacterTab = script.Parent.Parent
local Console = CharacterTab.Parent.Parent
local Controls = require(Console.Controls)
local EditorStore = require(CharacterTab.EditorStore)
local Parts = require(CharacterTab.Parts)

local e = React.createElement

local LABEL = 150

local function Stats(props: Parts.SectionProps)
	local editor, schema, state = props.editor, props.schema, props.state
	local served = if type(state.stats) == "table" then state.stats else {}
	local defaults: { [string]: number } = {}
	for _, stat in ipairs(schema.stats) do
		defaults[stat.name] = stat.default
	end

	local names: { string } = {}
	local values: { [string]: number } = {}
	for _, stat in ipairs(schema.stats) do
		local value = EditorStore.value(editor, `stats.{stat.name}`, served[stat.name])
		if type(value) == "number" then
			table.insert(names, stat.name)
			values[stat.name] = value
		end
	end

	local children: { [string]: any } = {}
	for index, name in ipairs(names) do
		local path = `stats.{name}`
		children[`s{index}`] = e(Parts.Line, { layoutOrder = index }, {
			Label = e(Parts.Label, { text = name, width = LABEL }),
			Field = e(Controls.Field, {
				value = Parts.number(values[name]),
				width = 80,
				invalid = EditorStore.isInvalid(editor, path),
				layoutOrder = 1,
				onCommit = function(text)
					local number = tonumber(text)
					if number then
						EditorStore.edit(path, number, { stats = { [name] = number } })
					end
				end,
			}),
			Default = e(Parts.Note, { text = `default {Parts.number(defaults[name] or 0)}`, fill = true, layoutOrder = 2 }),
			Remove = e(Controls.IconButton, {
				glyph = "close",
				layoutOrder = 3,
				onActivated = function()
					EditorStore.edit(path, false, { stats = { [name] = false } }, true)
				end,
			}),
		})
	end

	local options: { Controls.SearchItem } = {}
	for _, stat in ipairs(schema.stats) do
		if values[stat.name] == nil then
			table.insert(options, { key = stat.name, label = stat.name, detail = `default {Parts.number(stat.default)}` })
		end
	end
	children.Add = e(Parts.Line, { layoutOrder = 1000 }, {
		Add = e(Controls.Search, {
			items = options,
			placeholder = "add a stat",
			fill = true,
			layoutOrder = 1,
			onPick = function(name)
				local value = defaults[name] or 0
				EditorStore.edit(`stats.{name}`, value, { stats = { [name] = value } }, true)
			end,
		}),
	})
	children.Problem = e(Parts.Problem, { message = EditorStore.errorFor(editor, { "stats" }), layoutOrder = 1001 })

	return e(Controls.Section, {
		title = "Base stat overrides",
		summary = if #names > 0 then table.concat(names, ", ") else "none",
		open = props.open,
		onToggle = props.onToggle,
		layoutOrder = props.layoutOrder,
	}, children)
end

return Stats
