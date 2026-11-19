--!strict
-- Pools: per pool a slider, an exact field ("81" or "60%"), the live current / max, and a hold
-- switch that pins the pool where it is (dev/Characters/Holds); Fill all / Empty all.
--
-- The read-out follows the replicated stats (EditorStore samples them), so it moves with a fight.
-- A value is always sent as a fraction of the maximum, which says exactly what was meant whatever
-- the amount (the spec reads anything up to 1 as a fraction).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local CharacterTab = script.Parent.Parent
local Console = CharacterTab.Parent.Parent
local Controls = require(Console.Controls)
local Theme = require(Console.Theme)
local EditorStore = require(CharacterTab.EditorStore)
local Parts = require(CharacterTab.Parts)

local e = React.createElement
local size = Theme.size
local space = Theme.space

local function Pools(props: Parts.SectionProps)
	local editor, schema, state = props.editor, props.schema, props.state
	local dragging, setDragging = React.useState(nil :: { pool: string, ratio: number }?)

	local shown: { string } = {}
	local children: { [string]: any } = {}
	local notFull: { string } = {}
	local held: { string } = {}
	for index, name in ipairs(schema.pools) do
		local served = state.pools[name]
		local live = editor.pools[name]
		local max = if live then live.max elseif served then served.max else 0
		if max <= 0 then
			continue
		end
		table.insert(shown, name)
		local current = if live then live.current else served.current
		local path = `pools.{name}`
		local pending = editor.optimistic[path]
		local ratio = if dragging and dragging.pool == name
			then dragging.ratio
			elseif pending ~= nil then pending
			else current / max
		local value = ratio * max
		local isHeld = served and served.held ~= nil
		if ratio < 0.995 then
			table.insert(notFull, `{name} {Parts.round(ratio * 100)}%`)
		end
		if isHeld then
			table.insert(held, name)
		end

		local function send(fraction: number)
			EditorStore.edit(path, fraction, { pools = { [name] = fraction } }, true)
		end

		children[name] = e(Parts.Line, { layoutOrder = index }, {
			Label = e(Parts.Label, { text = name, width = 64 }),
			Slider = e(Controls.Slider, {
				ratio = ratio,
				layoutOrder = 1,
				onChange = function(next, done)
					if done then
						setDragging(nil)
						send(math.floor(next * 1000 + 0.5) / 1000)
					else
						setDragging({ pool = name, ratio = next })
					end
				end,
			}),
			Field = e(Controls.Field, {
				value = tostring(Parts.round(value)),
				width = 54,
				alignX = Enum.TextXAlignment.Right,
				invalid = EditorStore.isInvalid(editor, path),
				layoutOrder = 2,
				onCommit = function(text)
					local percent = string.match(text, "^%s*([%d%.]+)%s*%%%s*$")
					local fraction: number? = nil
					if percent and tonumber(percent) then
						fraction = (tonumber(percent) :: number) / 100
					elseif tonumber(text) then
						fraction = (tonumber(text) :: number) / max
					end
					if fraction then
						send(math.clamp(fraction, 0, 1))
					end
				end,
			}),
			Max = e(Controls.Text, {
				text = `/ {Parts.round(max)}`,
				mono = true,
				tone = "dim",
				size = size.monoSmall,
				height = space.control,
				width = UDim.new(0, 44),
				layoutOrder = 3,
			}),
			HoldLabel = e(Controls.Text, {
				text = "hold",
				tone = if isHeld then "ok" else "dim",
				size = size.small,
				height = space.control,
				autoWidth = true,
				layoutOrder = 4,
			}),
			Hold = e(Controls.Switch, {
				value = isHeld == true,
				busy = editor.sending,
				layoutOrder = 5,
				onToggle = function()
					EditorStore.command(`character hold {name} {if isHeld then "off" else "on"}`, "hold:" .. name)
				end,
			}),
		})
	end

	local function all(fraction: number)
		local patch: { [string]: number } = {}
		for _, name in ipairs(shown) do
			patch[name] = fraction
		end
		for _, name in ipairs(shown) do
			EditorStore.edit(`pools.{name}`, fraction, { pools = patch }, true)
		end
	end
	children.Actions = e(Parts.Line, { layoutOrder = 100 }, {
		Fill = e(Controls.Button, {
			text = "Fill all",
			layoutOrder = 1,
			onActivated = function()
				all(1)
			end,
		}),
		Empty = e(Controls.Button, {
			text = "Empty all",
			layoutOrder = 2,
			onActivated = function()
				all(0)
			end,
		}),
		Note = e(Parts.Note, { text = "hold keeps a pool at its value", fill = true, layoutOrder = 3 }),
	})
	children.Problem = e(Parts.Problem, { message = EditorStore.errorFor(editor, { "pools" }), layoutOrder = 200 })

	local summary = if #notFull > 0 then table.concat(notFull, " · ") else "all full"
	if #held > 0 then
		summary ..= ` · {table.concat(held, ", ")} held`
	end
	return e(Controls.Section, {
		title = "Pools",
		summary = summary,
		open = props.open,
		onToggle = props.onToggle,
		layoutOrder = props.layoutOrder,
	}, children)
end

return Pools
