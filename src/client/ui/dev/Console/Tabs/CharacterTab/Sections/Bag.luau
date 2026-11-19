--!strict
-- Bag: a row per item with a count stepper (stackable items), edit (the item editor under the row)
-- and remove, and a search to add an item.
--
-- A bag edit sends the whole bag, but an unchanged item goes as `{ keep = i }` (its place in the
-- served state), so its exact rolls stay and the patch stays small.

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

local COUNT_WIDTH = 92

-- The served bag as editable rows: each remembers which served item it is (`keep`) until changed.
local function servedRows(state: any): { any }
	local rows = {}
	for index, row in ipairs(Parts.list(state.bag)) do
		local copy = table.clone(row)
		copy.keep = index
		copy.served = row.count
		table.insert(rows, copy)
	end
	return rows
end

local function patchOf(rows: { any }): { any }
	local bag = {}
	for _, row in ipairs(rows) do
		if row.keep then
			table.insert(bag, if row.count ~= row.served then { keep = row.keep, count = row.count } else { keep = row.keep })
		else
			table.insert(bag, Parts.itemSpec(row))
		end
	end
	return bag
end

local function Bag(props: Parts.SectionProps)
	local editor, schema, state = props.editor, props.schema, props.state
	local editing, setEditing = React.useState(nil :: number?)
	local rows: { any } = EditorStore.value(editor, "bag", servedRows(state))

	local function setRows(nextRows: { any }, immediate: boolean?)
		EditorStore.edit("bag", nextRows, { bag = patchOf(nextRows) }, immediate)
	end

	local children: { [string]: any } = {}
	for index, row in ipairs(rows) do
		local stackable = (row.stackLimit or 1) > 1
		local left = if stackable
			then e(Controls.Stepper, {
				value = row.count or 1,
				min = 1,
				max = row.stackLimit * 10,
				width = 40,
				layoutOrder = 0,
				onChange = function(count)
					local nextRows = table.clone(rows)
					local copy = table.clone(row)
					copy.count = count
					nextRows[index] = copy
					setRows(nextRows)
				end,
			})
			else e(Controls.Text, {
				text = "×1",
				mono = true,
				tone = "dim",
				size = size.monoSmall,
				height = space.control,
				width = UDim.new(0, COUNT_WIDTH),
				alignX = Enum.TextXAlignment.Center,
				layoutOrder = 0,
			})
		children[`r{index}`] = e(Parts.Line, { layoutOrder = index * 2 }, {
			Count = left,
			Id = e(Controls.Text, { text = row.itemId, mono = true, size = size.monoSmall, height = space.control, autoWidth = true, layoutOrder = 1 }),
			Detail = e(Controls.Text, {
				text = Parts.itemDetail(row),
				tone = "dim",
				size = size.secondary,
				height = space.control,
				fill = true,
				layoutOrder = 2,
			}),
			Edit = e(Controls.IconButton, {
				glyph = "pencil",
				color = if editing == index then Theme.color.text else nil,
				layoutOrder = 3,
				onActivated = function()
					setEditing(if editing == index then nil else index)
				end,
			}),
			Remove = e(Controls.IconButton, {
				glyph = "close",
				layoutOrder = 4,
				onActivated = function()
					setEditing(nil)
					local nextRows = table.clone(rows)
					table.remove(nextRows, index)
					setRows(nextRows, true)
				end,
			}),
		})
		if editing == index then
			children[`e{index}`] = e(ItemEditor, {
				schema = schema,
				row = row,
				layoutOrder = index * 2 + 1,
				onDone = function()
					setEditing(nil)
				end,
				onChange = function(nextRow)
					local copy = table.clone(nextRow)
					copy.keep = nil
					local nextRows = table.clone(rows)
					nextRows[index] = copy
					setRows(nextRows)
				end,
			})
		end
	end

	local options: { Controls.SearchItem } = {}
	for _, item in ipairs(schema.items) do
		table.insert(options, {
			key = item.id,
			label = item.id,
			kind = item.name,
			detail = if item.stackLimit > 1 then `stacks to {item.stackLimit}` elseif item.equipment then table.concat(item.slots, ", ") else nil,
		})
	end
	children.Add = e(Parts.Line, { layoutOrder = 10000 }, {
		Spacer = e("Frame", { Size = UDim2.fromOffset(COUNT_WIDTH, 1), BackgroundTransparency = 1, LayoutOrder = 0 }),
		Add = e(Controls.Search, {
			items = options,
			placeholder = "add an item",
			fill = true,
			layoutOrder = 1,
			onPick = function(itemId)
				local def = Parts.itemDef(schema, itemId)
				local nextRows = table.clone(rows)
				table.insert(nextRows, {
					itemId = itemId,
					name = if def then def.name else itemId,
					count = 1,
					stackLimit = if def then def.stackLimit else 1,
					rarity = if def and def.equipment then def.rarities[1] else nil,
					affixes = if def and def.equipment then {} else nil,
				})
				setRows(nextRows, true)
			end,
		}),
	})
	children.Problem = e(Parts.Problem, { message = EditorStore.errorFor(editor, { "bag", "capacity" }), layoutOrder = 10001 })

	return e(Controls.Section, {
		title = "Bag",
		summary = `{#rows} of {state.capacity or schema.capacity.default}`,
		open = props.open,
		onToggle = props.onToggle,
		layoutOrder = props.layoutOrder,
	}, children)
end

return Bag
