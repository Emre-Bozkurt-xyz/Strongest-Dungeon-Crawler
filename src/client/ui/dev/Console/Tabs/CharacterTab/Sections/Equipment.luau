--!strict
-- Equipment: a row per filled equip slot (item, rarity, affixes) with edit and clear; editing opens
-- the item editor under the row. Empty slots are counted, with a search to equip an item into one.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local CharacterTab = script.Parent.Parent
local Console = CharacterTab.Parent.Parent
local Controls = require(Console.Controls)
local Theme = require(Console.Theme)
local EditorStore = require(CharacterTab.EditorStore)
local Parts = require(CharacterTab.Parts)
local ItemEditor = require(CharacterTab.ItemEditor)

local e = React.createElement
local size = Theme.size
local space = Theme.space

local SLOT_WIDTH = 84

local function ItemLine(props: { label: string, labelWidth: number?, row: any, onEdit: () -> (), onRemove: () -> (), editing: boolean, left: any?, layoutOrder: number })
	return e(Parts.Line, { layoutOrder = props.layoutOrder }, {
		Label = if props.left then nil else e(Parts.Label, { text = props.label, width = props.labelWidth or SLOT_WIDTH }),
		Left = props.left,
		Id = e(Controls.Text, {
			text = props.row.itemId,
			mono = true,
			size = size.monoSmall,
			height = space.control,
			autoWidth = true,
			layoutOrder = 1,
		}),
		Detail = e(Controls.Text, {
			text = Parts.itemDetail(props.row),
			tone = "dim",
			size = size.secondary,
			height = space.control,
			fill = true,
			layoutOrder = 2,
		}),
		Edit = e(Controls.IconButton, {
			glyph = "pencil",
			color = if props.editing then Theme.color.text else nil,
			layoutOrder = 3,
			onActivated = props.onEdit,
		}),
		Remove = e(Controls.IconButton, { glyph = "close", layoutOrder = 4, onActivated = props.onRemove }),
	})
end

local function Equipment(props: Parts.SectionProps)
	local editor, schema, state = props.editor, props.schema, props.state
	local editing, setEditing = React.useState(nil :: string?)
	local children: { [string]: any } = {}
	local filled = 0
	local empty: { string } = {}
	local shown: { [string]: boolean } = {}

	for index, slot in ipairs(schema.equipSlots) do
		local path = `equipment.{slot}`
		local row = EditorStore.value(editor, path, state.equipment[slot])
		if row == false then
			row = nil
		end
		if not row then
			table.insert(empty, slot)
			continue
		end
		filled += 1
		children[`s{index}`] = e(ItemLine, {
			label = slot,
			row = row,
			editing = editing == slot,
			layoutOrder = index * 3,
			onEdit = function()
				setEditing(if editing == slot then nil else slot)
			end,
			onRemove = function()
				if editing == slot then
					setEditing(nil)
				end
				EditorStore.edit(path, false, { equipment = { [slot] = false } }, true)
			end,
		})
		if editing == slot then
			children[`e{index}`] = e(ItemEditor, {
				schema = schema,
				row = row,
				slot = slot,
				layoutOrder = index * 3 + 1,
				onDone = function()
					setEditing(nil)
				end,
				onChange = function(nextRow)
					EditorStore.edit(path, nextRow, { equipment = { [slot] = Parts.itemSpec(nextRow) } })
				end,
			})
		end
		local problem = EditorStore.errorFor(editor, { path })
		if problem then
			shown[problem] = true
			children[`p{index}`] = e(Parts.Problem, { message = problem, layoutOrder = index * 3 + 2 })
		end
	end

	local options: { Controls.SearchItem } = {}
	for _, slot in ipairs(empty) do
		for _, item in ipairs(schema.items) do
			if table.find(item.slots, slot) then
				table.insert(options, { key = `{slot}|{item.id}`, label = item.id, kind = item.name, detail = `→ {slot}` })
			end
		end
	end
	children.Empty = e(Parts.Line, { layoutOrder = 1000 }, {
		Label = e(Parts.Label, { text = `{#empty} empty`, tone = "dim", width = SLOT_WIDTH }),
		Add = e(Controls.Search, {
			items = options,
			placeholder = "equip an item",
			fill = true,
			layoutOrder = 1,
			onPick = function(key)
				local slot, itemId = string.match(key, "^([^|]+)|(.+)$")
				if not slot or not itemId then
					return
				end
				local def = Parts.itemDef(schema, itemId)
				local row = {
					itemId = itemId,
					name = if def then def.name else itemId,
					rarity = if def then def.rarities[1] else nil,
					affixes = {},
				}
				EditorStore.edit(`equipment.{slot}`, row, { equipment = { [slot] = Parts.itemSpec(row) } }, true)
			end,
		}),
	})
	local problem = EditorStore.errorFor(editor, { "equipment" })
	children.Problem = e(Parts.Problem, { message = if problem and not shown[problem] then problem else nil, layoutOrder = 1001 })

	return e(Controls.Section, {
		title = "Equipment",
		summary = `{filled} of {#schema.equipSlots} slots`,
		open = props.open,
		onToggle = props.onToggle,
		layoutOrder = props.layoutOrder,
	}, children)
end

return Equipment
