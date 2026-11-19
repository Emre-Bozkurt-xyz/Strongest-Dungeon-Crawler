--!strict
-- Commands: every registered command, client and server, as a row under its registry group, and the
-- selected one's form, built from its descriptor, in the detail pane. A command registered later
-- shows up here with a working form and no UI work; the other tabs are conveniences over the same
-- commands.
--
-- Arguments are positional on the command line, so an optional argument can only be left empty when
-- nothing after it is filled in -- unless it has a default, which is written in its place. The exact
-- line the form will run is shown above Run (and as the ghost command), which is also how the syntax
-- is learnt.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Console = script.Parent.Parent
local ConsoleStore = require(Console.ConsoleStore)
local Controls = require(Console.Controls)
local Autocomplete = require(Console.Autocomplete)
local Selection = require(Console.Selection)
local Theme = require(Console.Theme)

local e = React.createElement
local size = Theme.size

local TAB = "commands"

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
		return e(Controls.Select, {
			value = if props.value ~= "" then props.value else nil,
			choices = arg.choices or {},
			placeholder = if arg.optional then "(leave empty)" else "choose",
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
			options[`o{index}`] = e(Controls.Chip, {
				text = if option == "" then "unset" else option,
				mono = option ~= "",
				selected = props.value == option,
				layoutOrder = index,
				onActivated = function()
					props.onChange(option)
				end,
			})
		end
		return e(Controls.Line, { inset = false, vertical = 0, gap = 6 }, options)
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
	return e(Controls.Input, {
		text = props.value,
		placeholder = placeholder,
		mono = arg.type ~= "string",
		invalid = invalid,
		onChange = props.onChange,
	})
end

local function argHint(arg: any): string
	local hint = arg.type .. (if arg.optional then " · optional" else "")
	if arg.default ~= nil and type(arg.default) ~= "table" then
		hint ..= ` · default {tostring(arg.default)}`
	end
	if arg.min ~= nil or arg.max ~= nil then
		hint ..= ` · {if arg.min ~= nil then tostring(arg.min) else ""}–{if arg.max ~= nil then tostring(arg.max) else ""}`
	end
	return hint
end

local function CommandsTab(props: { snapshot: ConsoleStore.State })
	local snapshot = props.snapshot
	local filter, setFilter = React.useState("")
	-- Each command's form values, kept per command so moving between rows loses nothing.
	local forms, setForms = React.useState({} :: { [string]: { [string]: string } })
	local needle = string.lower(filter)

	local groups: { string } = {}
	local members: { [string]: { any } } = {}
	local byName: { [string]: any } = {}
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
			byName[descriptor.name] = descriptor
		end
	end

	local keys: { string } = {}
	for _, group in ipairs(groups) do
		for _, descriptor in ipairs(members[group]) do
			table.insert(keys, descriptor.name)
		end
	end
	local selectedName = Selection.resolve(snapshot, TAB, keys)
	local selected = selectedName and byName[selectedName]
	local values = if selected then forms[selected.name] or {} else {}
	local line: string?, problem: string? = nil, nil
	if selected then
		line, problem = buildLine(selected, values)
	end
	local runKey = if selected then "cmd:" .. selected.name else ""

	local primary: ConsoleStore.Primary? = if selected
		then {
			label = "Run",
			command = line,
			fill = selected.name .. " ",
			options = { key = runKey, refresh = ConsoleStore.ALL_LISTS },
			enabled = line ~= nil,
		}
		else nil
	Selection.usePublish(TAB, { keys = keys, selected = selectedName, primary = primary })

	local children: { [string]: any } = {}
	local order = 0
	for groupIndex, group in ipairs(groups) do
		order += 1
		children[`g{groupIndex}`] = e(Controls.SectionLabel, {
			text = `{group} · {#members[group]}`,
			first = groupIndex == 1,
			layoutOrder = order,
		})
		for _, descriptor in ipairs(members[group]) do
			order += 1
			children[descriptor.name] = e(Controls.Row, {
				title = descriptor.name,
				mono = true,
				titleWidth = 150,
				selected = descriptor.name == selectedName,
				onSelect = function()
					ConsoleStore.pick(TAB, descriptor.name)
				end,
				body = {
					Summary = e(Controls.Text, {
						text = descriptor.summary,
						tone = "secondary",
						size = size.secondary,
						height = Theme.space.row,
						fill = true,
						layoutOrder = 1,
					}),
					Realm = if descriptor.realm == "client" then e(Controls.Chip, { text = "client", layoutOrder = 2 }) else nil,
				},
				layoutOrder = order,
			})
		end
	end
	if #groups == 0 then
		children.Empty = e(Controls.Empty, {
			text = if #snapshot.descriptors == 0 then "Reading commands…" else "No command matches.",
			layoutOrder = 1,
		})
	end

	local top = e(Controls.Line, { vertical = 8, gap = 6 }, {
		Filter = e(Controls.Input, {
			text = filter,
			placeholder = `Filter {#snapshot.descriptors} commands`,
			mono = false,
			fill = true,
			onChange = setFilter,
			layoutOrder = 1,
		}),
		Refresh = e(Controls.Button, { text = "Refresh", layoutOrder = 2, onActivated = ConsoleStore.refreshDescriptors }),
	})

	local detail: any = nil
	if selected then
		local result = snapshot.results[runKey]
		local form: { [string]: any } = {}
		for index, arg in ipairs(selected.args or {}) do
			form[`a{index}`] = e(Controls.FormRow, { label = arg.name, hint = argHint(arg), layoutOrder = index }, {
				Input = e("Frame", { Size = UDim2.fromScale(1, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1 }, {
					Input = e(ArgInput, {
						arg = arg,
						value = values[arg.name] or "",
						onChange = function(text: string)
							local copy = table.clone(forms)
							local entry = table.clone(copy[selected.name] or {})
							entry[arg.name] = text
							copy[selected.name] = entry
							setForms(copy)
						end,
					}),
				}),
			})
		end
		local extra: { [string]: any } = {
			Form = if #(selected.args or {}) > 0 then e(Controls.Stack, { gap = 6, layoutOrder = 1 }, form) else nil,
			Line = e(Controls.Text, {
				text = if line then "› " .. line else "× " .. (problem or ""),
				mono = line ~= nil,
				size = if line then size.monoSmall else size.secondary,
				tone = if line then "secondary" else "bad",
				wrap = true,
				layoutOrder = 2,
			}),
			Result = e(Controls.Result, { result = result, layoutOrder = 3 }),
		}
		if result and result.data ~= nil then
			local ok, encoded = pcall(HttpService.JSONEncode, HttpService, result.data)
			if ok and encoded ~= "[]" and encoded ~= "{}" then
				extra.Data = e(Controls.CodeView, { text = encoded, height = 120, layoutOrder = 4 })
			end
		end
		detail = e(Controls.DetailPane, {
			title = selected.name,
			id = `{selected.group} · {selected.realm or "server"}`,
			description = selected.summary,
			actions = {
				Run = e(Controls.Button, {
					text = "Run",
					primary = true,
					kbd = true,
					enabled = line ~= nil,
					busy = snapshot.busy[runKey],
					layoutOrder = 1,
					onActivated = function()
						if line then
							ConsoleStore.run(line, { key = runKey, refresh = ConsoleStore.ALL_LISTS })
						end
					end,
				}),
				Clear = e(Controls.Button, {
					text = "Clear",
					enabled = next(values) ~= nil or result ~= nil,
					layoutOrder = 2,
					onActivated = function()
						local copy = table.clone(forms)
						copy[selected.name] = nil
						setForms(copy)
						ConsoleStore.clearResult(runKey)
					end,
				}),
			},
		}, extra)
	end

	return e(Controls.TabLayout, { top = top, detail = detail }, children)
end

return CommandsTab
