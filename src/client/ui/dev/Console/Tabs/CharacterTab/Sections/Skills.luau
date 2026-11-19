--!strict
-- Skills and bar: owned skills as chips (click one to remove it) with a search to add one; each bar
-- set as a row of slot pickers limited to owned skills (or empty), and which set is active.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local CharacterTab = script.Parent.Parent
local Console = CharacterTab.Parent.Parent
local Controls = require(Console.Controls)
local EditorStore = require(CharacterTab.EditorStore)
local Parts = require(CharacterTab.Parts)

local e = React.createElement

local function Skills(props: Parts.SectionProps)
	local editor, schema, state = props.editor, props.schema, props.state
	local owned: { string } = Parts.list(EditorStore.value(editor, "skills", state.skills))
	local bar: { { string } } = Parts.list(EditorStore.value(editor, "bar", state.bar))
	local activeSet: number = EditorStore.value(editor, "activeSet", state.activeSet)
	local slotsPerSet = schema.bar.slots

	local function setSkills(list: { string })
		EditorStore.edit("skills", list, { skills = list }, true)
	end

	local chips: { [string]: any } = {
		Layout = Controls.list(Enum.FillDirection.Horizontal, 6, { Wraps = true }),
	}
	for index, skill in ipairs(owned) do
		chips[`s{index}`] = e(Controls.Chip, {
			text = `{skill}  ×`,
			layoutOrder = index,
			onActivated = function()
				local list = table.clone(owned)
				table.remove(list, index)
				setSkills(list)
			end,
		})
	end
	local addable: { Controls.SearchItem } = {}
	for _, skill in ipairs(schema.skills) do
		if not table.find(owned, skill.id) then
			table.insert(addable, { key = skill.id, label = skill.name })
		end
	end
	chips.Add = e(Controls.Search, {
		items = addable,
		placeholder = "add a skill",
		width = 150,
		layoutOrder = 1000,
		onPick = function(skillId)
			local list = table.clone(owned)
			table.insert(list, skillId)
			setSkills(list)
		end,
	})

	local children: { [string]: any } = {
		Owned = e(Parts.Line, { auto = true, layoutOrder = 1 }, {
			Label = e(Parts.Label, { text = "Owned", width = 64 }),
			Chips = e("Frame", {
				Size = UDim2.fromOffset(0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				LayoutOrder = 1,
			}, Controls.mergeInto({ Flex = e("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }) }, chips)),
		}),
		SkillsProblem = e(Parts.Problem, { message = EditorStore.errorFor(editor, { "skills" }), layoutOrder = 2 }),
	}

	for setIndex = 1, schema.bar.sets do
		local slots = bar[setIndex] or {}
		children[`h{setIndex}`] = e(Parts.Line, { layoutOrder = 10 + setIndex * 2 }, {
			Set = e(Controls.Chip, {
				text = `Set {setIndex}`,
				selected = setIndex == activeSet,
				layoutOrder = 1,
				onActivated = function()
					if setIndex ~= activeSet then
						EditorStore.edit("activeSet", setIndex, { activeSet = setIndex }, true)
					end
				end,
			}),
			Active = e(Parts.Note, {
				text = if setIndex == activeSet then "active" else "click to make active",
				tone = if setIndex == activeSet then "ok" else "dim",
				layoutOrder = 2,
			}),
		})
		local row: { [string]: any } = {}
		for slot = 1, slotsPerSet do
			local skill = slots[slot]
			row[`s{slot}`] = e(Controls.Select, {
				value = if skill and skill ~= "" then skill else nil,
				choices = owned,
				allowClear = true,
				clearLabel = "(empty)",
				placeholder = "—",
				compact = true,
				fill = true,
				layoutOrder = slot,
				onPick = function(value)
					local nextBar = {}
					for index = 1, schema.bar.sets do
						local set = table.clone(bar[index] or {})
						for fill = 1, slotsPerSet do
							set[fill] = set[fill] or ""
						end
						nextBar[index] = set
					end
					nextBar[setIndex][slot] = value or ""
					EditorStore.edit("bar", nextBar, { bar = nextBar }, true)
				end,
			})
		end
		children[`r{setIndex}`] = e(Parts.Line, { gap = 6, layoutOrder = 11 + setIndex * 2 }, row)
	end
	children.BarProblem = e(Parts.Problem, { message = EditorStore.errorFor(editor, { "bar", "activeSet" }), layoutOrder = 100 })

	return e(Controls.Section, {
		title = "Skills and bar",
		summary = `{#owned} owned · {schema.bar.sets} sets`,
		open = props.open,
		onToggle = props.onToggle,
		layoutOrder = props.layoutOrder,
	}, children)
end

return Skills
