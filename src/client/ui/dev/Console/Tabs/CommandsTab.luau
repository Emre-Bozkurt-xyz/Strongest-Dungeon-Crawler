--!strict
-- Commands: every registered command, client and server, grouped as the registry groups them, each
-- with a form built from its descriptor. A command registered later shows up here with a working form
-- and no UI work; the other tabs are conveniences over the same commands.
--
-- Arguments are positional on the command line, so an optional argument can only be left empty when
-- nothing after it is filled in -- unless it has a default, which is written in its place. The line
-- the form will run is shown under it, which is also how the syntax is learnt.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Console = script.Parent.Parent
local ThemeContext = require(Console.Parent.Parent.hooks.ThemeContext)
local ConsoleStore = require(Console.ConsoleStore)
local Controls = require(Console.Controls)
local Autocomplete = require(Console.Autocomplete)

local e = React.createElement

-- Builds the command line from the form's values. Returns the line, or nil and why it cannot run.
local function buildLine(descriptor: any, values: { [string]: string }): (string?, string?)
	local args = descriptor.args or {}
	local last = 0
	for index, arg in ipairs(args) do
		if (values[arg.name] or "") ~= "" then
			last = index
		end
	end
	local parts = { descriptor.name }
	for index, arg in ipairs(args) do
		local value = values[arg.name] or ""
		if value == "" then
			if not arg.optional then
				return nil, `{arg.name} is required`
			end
			if index < last then
				if arg.default == nil then
					local later = args[last].name
					return nil, `fill {arg.name} too, or leave {later} empty (arguments are positional)`
				end
				value = if type(arg.default) == "table" then HttpService:JSONEncode(arg.default) else tostring(arg.default)
			end
		end
		if value ~= "" then
			if arg.type == "json" then
				local ok, decoded = pcall(HttpService.JSONDecode, HttpService, value)
				if not ok or type(decoded) ~= "table" then
					return nil, `{arg.name} is not a JSON object or array`
				end
				table.insert(parts, value)
			elseif arg.type == "rest" then
				table.insert(parts, value)
			elseif arg.type == "number" or arg.type == "integer" then
				local number = tonumber(value)
				if number == nil then
					return nil, `{arg.name} must be a number`
				end
				if arg.type == "integer" and number % 1 ~= 0 then
					return nil, `{arg.name} must be a whole number`
				end
				table.insert(parts, value)
			else
				table.insert(parts, Controls.quote(value))
			end
		end
	end
	return table.concat(parts, " "), nil
end

local function ArgInput(props: { arg: any, value: string, onChange: (string) -> () })
	local arg = props.arg
	if arg.type == "choice" then
		return e(Controls.Choice, {
			value = if props.value ~= "" then props.value else nil,
			choices = arg.choices or {},
			placeholder = if arg.optional then "(leave empty)" else "choose…",
			allowClear = arg.optional,
			onPick = function(picked: string?)
				props.onChange(picked or "")
			end,
		})
	elseif arg.type == "boolean" then
		local options: { [string]: any } = {}
		local values = { "true", "false" }
		if arg.optional then
			table.insert(values, 1, "")
		end
		for index, option in ipairs(values) do
			options[`o{index}`] = e(Controls.Button, {
				text = if option == "" then "unset" else option,
				selected = props.value == option,
				layoutOrder = index,
				onActivated = function()
					props.onChange(option)
				end,
			})
		end
		return e(Controls.Row, {}, options)
	end
	local placeholder = Autocomplete.describeArg(arg)
	if arg.type == "json" then
		placeholder = if arg.optional then '{"key": 1}  (optional)' else '{"key": 1}'
	end
	local invalid = false
	if props.value ~= "" and (arg.type == "number" or arg.type == "integer") then
		invalid = tonumber(props.value) == nil
	elseif props.value ~= "" and arg.type == "json" then
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, props.value)
		invalid = not ok or type(decoded) ~= "table"
	end
	return e(Controls.Field, {
		text = props.value,
		placeholder = placeholder,
		mono = arg.type ~= "string",
		invalid = invalid,
		onChange = props.onChange,
	})
end

local function CommandCard(props: { descriptor: any, snapshot: ConsoleStore.State, layoutOrder: number })
	local theme = ThemeContext.useTheme()
	local descriptor = props.descriptor
	local open, setOpen = React.useState(false)
	local values, setValues = React.useState({} :: { [string]: string })
	local key = "cmd:" .. descriptor.name
	local result = props.snapshot.results[key]

	local line, problem = buildLine(descriptor, values)

	local header = e("TextButton", {
		Text = "",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 1,
		[React.Event.Activated] = function()
			setOpen(not open)
		end,
	}, {
		Layout = e("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }),
		Top = e(Controls.Row, { layoutOrder = 1, gap = 8 }, {
			Caret = e(Controls.Label, {
				text = if open then "–" else "+",
				height = 26,
				width = UDim.new(0, 14),
				color = theme.color.textMuted,
				layoutOrder = 1,
			}),
			Name = e(Controls.Label, {
				text = descriptor.name,
				mono = true,
				bold = true,
				size = 18,
				height = 26,
				autoWidth = true,
				color = if open then theme.color.accent else theme.color.textPrimary,
				layoutOrder = 2,
			}),
			Realm = if descriptor.realm == "client"
				then e(Controls.Chip, { text = "client", color = theme.color.critical, layoutOrder = 3 })
				else nil,
		}),
		Summary = e(Controls.Label, {
			text = descriptor.summary,
			size = Controls.SMALL,
			wrap = true,
			color = theme.color.textMuted,
			layoutOrder = 2,
		}),
	})

	local children: { [string]: any } = { Header = header }
	if open then
		local form: { [string]: any } = {}
		for index, arg in ipairs(descriptor.args or {}) do
			local hint = arg.type .. (if arg.optional then " · optional" else "")
			if arg.default ~= nil and type(arg.default) ~= "table" then
				hint ..= ` · default {tostring(arg.default)}`
			end
			if arg.min ~= nil or arg.max ~= nil then
				hint ..= ` · {if arg.min ~= nil then tostring(arg.min) else ""}–{if arg.max ~= nil then tostring(arg.max) else ""}`
			end
			form[`a{index}`] = e(Controls.LabelledRow, {
				label = arg.name,
				hint = hint,
				labelWidth = 140,
				layoutOrder = index,
			}, {
				Input = e(ArgInput, {
					arg = arg,
					value = values[arg.name] or "",
					onChange = function(text: string)
						local copy = table.clone(values)
						copy[arg.name] = text
						setValues(copy)
					end,
				}),
			})
		end
		if #(descriptor.args or {}) == 0 then
			form.None = e(Controls.Label, { text = "No arguments.", size = Controls.SMALL, color = theme.color.textMuted, layoutOrder = 0 })
		end
		children.Form = e(Controls.Stack, { gap = 6, layoutOrder = 2 }, form)
		children.Line = e(Controls.Label, {
			text = if line then "› " .. line else "× " .. (problem or ""),
			mono = line ~= nil,
			bold = line == nil,
			size = Controls.MONO,
			wrap = true,
			color = if line then theme.color.textPrimary else theme.color.danger,
			layoutOrder = 3,
		})
		children.Actions = e(Controls.Row, { layoutOrder = 4 }, {
			Run = e(Controls.Button, {
				text = "Run",
				tone = "primary",
				enabled = line ~= nil,
				busy = props.snapshot.busy[key],
				layoutOrder = 1,
				onActivated = function()
					if line then
						ConsoleStore.run(line, { key = key, refresh = ConsoleStore.ALL_LISTS })
					end
				end,
			}),
			Clear = e(Controls.Button, {
				text = "Clear",
				enabled = next(values) ~= nil or result ~= nil,
				layoutOrder = 2,
				onActivated = function()
					setValues({})
					ConsoleStore.clearResult(key)
				end,
			}),
		})
		children.Result = e(Controls.ResultLine, { result = result, layoutOrder = 5 })
		if result and result.data ~= nil then
			local ok, encoded = pcall(HttpService.JSONEncode, HttpService, result.data)
			if ok and encoded ~= "[]" and encoded ~= "{}" then
				children.Data = e(Controls.CodeView, { text = encoded, height = 120, layoutOrder = 6 })
			end
		end
	end

	return e(Controls.Card, { layoutOrder = props.layoutOrder, current = open, gap = 8 }, children)
end

local function CommandsTab(props: { snapshot: ConsoleStore.State })
	local theme = ThemeContext.useTheme()
	local snapshot = props.snapshot
	local filter, setFilter = React.useState("")
	local needle = string.lower(filter)

	local groups: { string } = {}
	local members: { [string]: { any } } = {}
	for _, descriptor in ipairs(snapshot.descriptors) do
		local matches = needle == ""
			or string.find(descriptor.name, needle, 1, true) ~= nil
			or string.find(string.lower(descriptor.summary), needle, 1, true) ~= nil
			or string.find(string.lower(descriptor.group), needle, 1, true) ~= nil
		if matches then
			if not members[descriptor.group] then
				members[descriptor.group] = {}
				table.insert(groups, descriptor.group)
			end
			table.insert(members[descriptor.group], descriptor)
		end
	end

	local children: { [string]: any } = {
		Filter = e(Controls.Row, { layoutOrder = 0 }, {
			Field = e(Controls.Field, {
				text = filter,
				placeholder = `filter {#snapshot.descriptors} commands`,
				fill = true,
				onChange = setFilter,
				layoutOrder = 1,
			}),
			Refresh = e(Controls.Button, {
				text = "Refresh",
				layoutOrder = 2,
				onActivated = ConsoleStore.refreshDescriptors,
			}),
		}),
	}
	for groupIndex, group in ipairs(groups) do
		local cards: { [string]: any } = {}
		for index, descriptor in ipairs(members[group]) do
			cards[descriptor.name] = e(CommandCard, { descriptor = descriptor, snapshot = snapshot, layoutOrder = index })
		end
		children[`g{groupIndex}`] = e(Controls.Section, { title = `{group}  ({#members[group]})`, layoutOrder = groupIndex }, cards)
	end
	if #groups == 0 then
		children.Empty = e(Controls.Label, {
			text = if #snapshot.descriptors == 0 then "Reading commands…" else "No command matches.",
			color = theme.color.textMuted,
			layoutOrder = 1,
		})
	end
	return e(Controls.Stack, { gap = 14 }, children)
end

return CommandsTab
