--!strict
-- Level: a stepper for the level (which sets total XP to that level's threshold), the exact total XP,
-- and the XP to the next level.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local CharacterTab = script.Parent.Parent
local Controls = require(CharacterTab.Parent.Parent.Controls)
local EditorStore = require(CharacterTab.EditorStore)
local Parts = require(CharacterTab.Parts)

local e = React.createElement

local function levelOf(totals: { number }, xp: number): number
	local level = 1
	for index, total in ipairs(totals) do
		if xp >= total then
			level = index
		end
	end
	return level
end

local function Level(props: Parts.SectionProps)
	local editor, schema, state = props.editor, props.schema, props.state
	local totals: { number } = schema.level.totals
	local xp: number = EditorStore.value(editor, "level", state.xp)
	local level = levelOf(totals, xp)
	local nextTotal = totals[level + 1]
	local toNext = if nextTotal then nextTotal - xp else nil

	local function setXp(total: number)
		EditorStore.edit("level", total, { xp = total })
	end

	return e(Controls.Section, {
		title = "Level",
		summary = `{level} · {Parts.number(Parts.round(xp))} XP`,
		open = props.open,
		onToggle = props.onToggle,
		layoutOrder = props.layoutOrder,
	}, {
		Level = e(Parts.Line, { layoutOrder = 1 }, {
			Label = e(Parts.Label, { text = "Level" }),
			Stepper = e(Controls.Stepper, {
				value = level,
				min = 1,
				max = schema.level.max,
				width = 64,
				invalid = EditorStore.isInvalid(editor, "level"),
				layoutOrder = 1,
				onChange = function(value)
					EditorStore.edit("level", totals[value], { level = value })
				end,
			}),
			ToNext = e(Parts.Note, {
				text = if toNext then `{Parts.number(Parts.round(toNext))} XP to level {level + 1}` else "max level",
				layoutOrder = 2,
			}),
		}),
		Total = e(Parts.Line, { layoutOrder = 2 }, {
			Label = e(Parts.Label, { text = "Total XP" }),
			Field = e(Controls.Field, {
				value = Parts.number(math.floor(xp * 100 + 0.5) / 100),
				width = 110,
				invalid = EditorStore.isInvalid(editor, "level"),
				layoutOrder = 1,
				onCommit = function(text)
					local number = tonumber(text)
					if number and number >= 0 then
						setXp(number)
					end
				end,
			}),
			Floor = e(Parts.Note, { text = `level {level} starts at {Parts.number(totals[level])}`, layoutOrder = 2 }),
		}),
		Problem = e(Parts.Problem, { message = EditorStore.errorFor(editor, { "level" }), layoutOrder = 3 }),
	})
end

return Level
