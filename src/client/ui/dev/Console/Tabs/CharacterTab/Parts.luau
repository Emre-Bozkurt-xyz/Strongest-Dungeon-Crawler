--!strict
-- What the character editor's sections share: the line a section body is made of (inset under the
-- section title), its label column, the red line a refused edit leaves, number formatting, and the
-- props every section gets.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Console = script.Parent.Parent.Parent
local Controls = require(Console.Controls)
local Theme = require(Console.Theme)
local EditorStore = require(script.Parent.EditorStore)

local e = React.createElement
local size = Theme.size
local space = Theme.space

local Parts = {}

export type SectionProps = {
	editor: EditorStore.State,
	schema: any,
	state: any,
	open: boolean,
	onToggle: () -> (),
	layoutOrder: number?,
}

Parts.LABEL_WIDTH = 96

-- One line of a section body: inset under the section title, controls left to right. One control
-- high, so every line of a section keeps the same rhythm, unless `auto` (a line that wraps, or holds
-- wrapping text).
function Parts.Line(props: { gap: number?, wrap: boolean?, auto: boolean?, height: number?, layoutOrder: number?, children: any? })
	local auto = props.auto == true or props.wrap == true
	local children: { [string]: any } = {
		-- A line taller than one control reads from its top, label beside the first row.
		Layout = Controls.list(Enum.FillDirection.Horizontal, props.gap or space.gap, {
			Wraps = props.wrap == true,
			VerticalAlignment = if auto then Enum.VerticalAlignment.Top else Enum.VerticalAlignment.Center,
		}),
		Padding = e("UIPadding", {
			PaddingLeft = UDim.new(0, Controls.SECTION_INSET),
			PaddingRight = UDim.new(0, space.pad),
			PaddingTop = UDim.new(0, 3),
			PaddingBottom = UDim.new(0, 3),
		}),
	}
	Controls.mergeInto(children, props.children)
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, if auto then 0 else props.height or space.control + 6),
		AutomaticSize = if auto then Enum.AutomaticSize.Y else Enum.AutomaticSize.None,
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
	}, children)
end

-- The label column of a line.
function Parts.Label(props: { text: string, width: number?, tone: Controls.Tone?, layoutOrder: number? })
	return e(Controls.Text, {
		text = props.text,
		tone = props.tone or "secondary",
		size = size.secondary,
		height = space.control,
		width = UDim.new(0, props.width or Parts.LABEL_WIDTH),
		layoutOrder = props.layoutOrder or 0,
	})
end

-- Dim text that sizes to itself on a line.
function Parts.Note(props: { text: string, tone: Controls.Tone?, mono: boolean?, fill: boolean?, layoutOrder: number? })
	return e(Controls.Text, {
		text = props.text,
		tone = props.tone or "dim",
		mono = props.mono,
		size = if props.mono then size.monoSmall else size.secondary,
		height = space.control,
		autoWidth = not props.fill,
		fill = props.fill,
		layoutOrder = props.layoutOrder,
	})
end

-- Why the last refused edit in this part failed, in red, under the controls; nothing when none.
function Parts.Problem(props: { message: string?, layoutOrder: number? })
	if not props.message then
		return nil
	end
	return e(Parts.Line, { auto = true, layoutOrder = props.layoutOrder }, {
		Text = e(Controls.Text, {
			text = "×  " .. props.message,
			tone = "bad",
			size = size.secondary,
			wrap = true,
			layoutOrder = 1,
		}),
	})
end

function Parts.round(value: number): number
	return math.floor(value + 0.5)
end

-- A whole number when it is one, else at most two decimals.
function Parts.number(value: number): string
	if value == math.floor(value) then
		return string.format("%d", value)
	end
	local text = string.format("%.2f", value)
	text = string.gsub(text, "0+$", "")
	text = string.gsub(text, "%.$", "")
	return text
end

-- A JSON list from the server is an empty object when empty; either way, a Luau list.
function Parts.list(value: any): { any }
	return if type(value) == "table" then value else {}
end

-- An item as a spec for a patch: id, then the shorthands (rarity, item level, affixes by id and
-- tier). Positional keys are strings, as the server reads spec data.
function Parts.itemSpec(row: any): { [string]: any }
	local spec: { [string]: any } = { ["1"] = row.itemId }
	if row.count and row.count > 1 then
		spec["2"] = row.count
	end
	if row.rarity then
		spec.rarity = row.rarity
	end
	if row.itemLevel then
		spec.itemLevel = row.itemLevel
	end
	if row.affixes then
		local affixes = {}
		for _, affix in ipairs(row.affixes) do
			table.insert(affixes, if affix.tier then { ["1"] = affix.id, tier = affix.tier } else affix.id)
		end
		spec.affixes = affixes
	end
	return spec
end

-- "magic · fury, of_vigor" for an item row.
function Parts.itemDetail(row: any): string
	local parts: { string } = {}
	if row.rarity then
		table.insert(parts, row.rarity)
	end
	local affixes: { string } = {}
	for _, affix in ipairs(Parts.list(row.affixes)) do
		table.insert(affixes, if affix.tier and affix.tier > 1 then `{affix.id} t{affix.tier}` else affix.id)
	end
	if #affixes > 0 then
		table.insert(parts, table.concat(affixes, ", "))
	end
	return table.concat(parts, " · ")
end

-- The schema's item entry by id.
function Parts.itemDef(schema: any, itemId: string): any?
	for _, item in ipairs(schema.items) do
		if item.id == itemId then
			return item
		end
	end
	return nil
end

return Parts
