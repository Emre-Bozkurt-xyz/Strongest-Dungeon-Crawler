--!strict
-- The inline editor under an equipment or bag row: which item (limited to what the slot takes),
-- its rarity and item level, and its affixes with their tiers. Every change is handed up at once as
-- the new row; the section turns it into a patch. Affixes are named by id and tier, so the server
-- rolls their values afresh on each change.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Console = script.Parent.Parent.Parent
local Controls = require(Console.Controls)
local Theme = require(Console.Theme)
local Parts = require(script.Parent.Parts)

local e = React.createElement
local color = Theme.color
local size = Theme.size
local space = Theme.space

local LABEL = 64

local function ItemEditor(props: {
	schema: any,
	row: any,
	-- The equip slot the item sits in; nil for the bag.
	slot: string?,
	onChange: (row: any) -> (),
	onDone: () -> (),
	layoutOrder: number?,
})
	local schema, row = props.schema, props.row
	local def = Parts.itemDef(schema, row.itemId)
	local rootRef = React.useRef(nil :: GuiObject?)
	Controls.useHitRefresh(rootRef, { row.itemId, #Parts.list(row.affixes) })

	local itemChoices: { string } = {}
	local itemLabels: { [string]: string } = {}
	for _, item in ipairs(schema.items) do
		if not props.slot or table.find(item.slots, props.slot) then
			table.insert(itemChoices, item.id)
			itemLabels[item.id] = item.id
		end
	end

	local function change(patch: { [string]: any })
		local nextRow = table.clone(row)
		for key, value in pairs(patch) do
			nextRow[key] = value
		end
		props.onChange(nextRow)
	end

	local lines: { [string]: any } = {
		Layout = Controls.list(Enum.FillDirection.Vertical, 6),
		Padding = Controls.padding(10, 8),
		Corner = Controls.corner(),
		Stroke = Controls.outline(color.outline),
	}
	local function line(key: string, order: number, children: { [string]: any })
		lines[key] = e("Frame", {
			Size = UDim2.new(1, 0, 0, space.control),
			BackgroundTransparency = 1,
			LayoutOrder = order,
		}, Controls.mergeInto({ Layout = Controls.list(Enum.FillDirection.Horizontal, 6) }, children))
	end
	local function label(text: string): any
		return e(Controls.Text, { text = text, tone = "secondary", size = size.secondary, height = space.control, width = UDim.new(0, LABEL), layoutOrder = 0 })
	end

	line("Item", 1, {
		Label = label("Item"),
		Pick = e(Controls.Select, {
			value = row.itemId,
			choices = itemChoices,
			labels = itemLabels,
			fill = true,
			layoutOrder = 1,
			onPick = function(itemId)
				if not itemId or itemId == row.itemId then
					return
				end
				local nextDef = Parts.itemDef(schema, itemId)
				local rarity = row.rarity
				if nextDef and not table.find(nextDef.rarities, rarity) then
					rarity = nextDef.rarities[1]
				end
				change({
					itemId = itemId,
					name = if nextDef then nextDef.name else itemId,
					rarity = if nextDef and nextDef.equipment then rarity else nil,
					itemLevel = if nextDef and nextDef.equipment then row.itemLevel else nil,
					affixes = if nextDef and nextDef.equipment then {} else nil,
					count = if nextDef and nextDef.stackLimit > 1 then row.count else 1,
				})
			end,
		}),
	})

	if def and def.equipment then
		line("Rarity", 2, {
			Label = label("Rarity"),
			Pick = e(Controls.Select, {
				value = row.rarity,
				choices = def.rarities,
				width = 110,
				layoutOrder = 1,
				onPick = function(rarity)
					if rarity and rarity ~= row.rarity then
						change({ rarity = rarity })
					end
				end,
			}),
			LevelLabel = e(Controls.Text, { text = "level", tone = "secondary", size = size.secondary, height = space.control, autoWidth = true, layoutOrder = 2 }),
			Level = e(Controls.Field, {
				value = tostring(row.itemLevel or def.baseItemLevel or 1),
				width = 52,
				layoutOrder = 3,
				onCommit = function(text)
					local number = tonumber(text)
					if number and number >= 1 then
						change({ itemLevel = math.floor(number) })
					end
				end,
			}),
		})

		local affixes = Parts.list(row.affixes)
		local present: { [string]: boolean } = {}
		local byId: { [string]: any } = {}
		for _, affix in ipairs(def.affixes) do
			byId[affix.id] = affix
		end
		for index, affix in ipairs(affixes) do
			present[affix.id] = true
			local options = byId[affix.id]
			local tiers: { string } = {}
			for _, tier in ipairs(options and options.tiers or {}) do
				table.insert(tiers, tostring(tier))
			end
			line(`a{index}`, 10 + index, {
				Label = label(if index == 1 then "Affixes" else ""),
				Id = e(Controls.Text, {
					text = affix.id .. (if options then ` ({options.kind})` else ""),
					mono = true,
					size = size.monoSmall,
					height = space.control,
					fill = true,
					layoutOrder = 1,
				}),
				TierLabel = e(Controls.Text, { text = "tier", tone = "dim", size = size.small, height = space.control, autoWidth = true, layoutOrder = 2 }),
				Tier = e(Controls.Select, {
					value = if affix.tier then tostring(affix.tier) else nil,
					choices = tiers,
					placeholder = "any",
					width = 64,
					layoutOrder = 3,
					onPick = function(tier)
						local list = table.clone(affixes)
						list[index] = { id = affix.id, tier = tonumber(tier) }
						change({ affixes = list })
					end,
				}),
				Remove = e(Controls.IconButton, {
					glyph = "close",
					layoutOrder = 4,
					onActivated = function()
						local list = table.clone(affixes)
						table.remove(list, index)
						change({ affixes = list })
					end,
				}),
			})
		end
		local addable: { string } = {}
		local addLabels: { [string]: string } = {}
		for _, affix in ipairs(def.affixes) do
			if not present[affix.id] then
				table.insert(addable, affix.id)
				addLabels[affix.id] = `{affix.id} ({affix.kind})`
			end
		end
		line("Add", 50, {
			Label = label(if #affixes == 0 then "Affixes" else ""),
			Pick = e(Controls.Select, {
				value = nil,
				choices = addable,
				labels = addLabels,
				placeholder = if #addable > 0 then "add an affix" else "no other affix fits",
				enabled = #addable > 0,
				fill = true,
				layoutOrder = 1,
				onPick = function(affixId)
					if affixId then
						local list = table.clone(affixes)
						local options = byId[affixId]
						table.insert(list, { id = affixId, tier = if options then options.tiers[1] else nil })
						change({ affixes = list })
					end
				end,
			}),
		})
	end

	line("Done", 90, {
		Note = e(Controls.Text, {
			text = "each change rebuilds you and rerolls affix values",
			tone = "dim",
			size = size.small,
			height = space.control,
			fill = true,
			layoutOrder = 1,
		}),
		Done = e(Controls.Button, { text = "Done", layoutOrder = 2, onActivated = props.onDone }),
	})

	return e("Frame", {
		ref = rootRef,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
	}, {
		Padding = e("UIPadding", {
			PaddingLeft = UDim.new(0, Controls.SECTION_INSET),
			PaddingRight = UDim.new(0, space.pad),
			PaddingTop = UDim.new(0, 2),
			PaddingBottom = UDim.new(0, 6),
		}),
		Box = e("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = color.raised,
			BorderSizePixel = 0,
		}, lines),
	})
end

return ItemEditor
