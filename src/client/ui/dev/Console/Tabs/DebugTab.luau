--!strict
-- Debug: server and client debug flags as switches, and client tuning overrides.
--
-- Flags are read with `flags` / `cflags` and flipped with `flag` / `cflag`. Tuning is changed only
-- through `tune set` / `tune reset`; the override list and the path suggestions are read from
-- DevTuningService directly, since asking `tune` for them would print every path to the output.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Console = script.Parent.Parent
local ui = Console.Parent.Parent
local ThemeContext = require(ui.hooks.ThemeContext)
local ConsoleStore = require(Console.ConsoleStore)
local Controls = require(Console.Controls)
local DevTuningService = require(ui.Parent.dev.DevTuningService)

local e = React.createElement

local MAX_PATH_SUGGESTIONS = 8

local function sortedKeys(map: { [string]: any }): { string }
	local keys: { string } = {}
	for key in pairs(map) do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

local function display(value: any): string
	if typeof(value) == "Vector3" then
		return string.format("%g, %g, %g", value.X, value.Y, value.Z)
	end
	if type(value) == "table" then
		return "{…}"
	end
	return tostring(value)
end

-- Every overridden leaf as path = value, sorted.
local function overrideLeaves(): { { path: string, value: any } }
	local out: { { path: string, value: any } } = {}
	local function walk(node: any, prefix: string)
		for key, value in pairs(node) do
			local path = if prefix == "" then tostring(key) else `{prefix}.{key}`
			if type(value) == "table" then
				walk(value, path)
			else
				table.insert(out, { path = path, value = value })
			end
		end
	end
	walk(DevTuningService.getOverrides(), "")
	table.sort(out, function(a, b)
		return a.path < b.path
	end)
	return out
end

local function useTuningRevision(): number
	local revision, setRevision = React.useState(0)
	React.useEffect(function()
		return DevTuningService.subscribe("", function()
			setRevision(function(n)
				return n + 1
			end)
		end)
	end, {})
	return revision
end

local function FlagList(props: {
	flags: { [string]: boolean }?,
	error: string?,
	command: string,
	refresh: ConsoleStore.ListName,
	snapshot: ConsoleStore.State,
})
	local theme = ThemeContext.useTheme()
	local rows: { [string]: any } = {}
	local flags = props.flags
	if not flags then
		rows.Empty = e(Controls.Label, {
			text = props.error or "Reading flags…",
			size = Controls.SMALL,
			color = if props.error then theme.color.danger else theme.color.textMuted,
		})
	else
		for index, name in ipairs(sortedKeys(flags)) do
			local on = flags[name] == true
			local key = `{props.command}:{name}`
			rows[`f{index}`] = e(Controls.Row, { layoutOrder = index, height = Controls.ROW }, {
				Toggle = e(Controls.Toggle, {
					value = on,
					busy = props.snapshot.busy[key],
					layoutOrder = 1,
					onToggle = function()
						ConsoleStore.run(`{props.command} {name} {if on then "false" else "true"}`, {
							key = key,
							refresh = { props.refresh },
						})
					end,
				}),
				Name = e(Controls.Label, {
					text = name,
					mono = true,
					size = Controls.MONO,
					height = Controls.ROW,
					autoWidth = true,
					color = if on then theme.color.textPrimary else theme.color.textMuted,
					layoutOrder = 2,
				}),
			})
		end
	end
	if not flags then
		return e(Controls.Stack, { gap = 2 }, rows)
	end
	-- Two columns: flag names are short, and one long column pushed tuning far down the tab.
	rows.Grid = e("UIGridLayout", {
		CellSize = UDim2.new(0.5, -4, 0, Controls.ROW),
		CellPadding = UDim2.fromOffset(8, 2),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, rows)
end

local function DebugTab(props: { snapshot: ConsoleStore.State })
	local theme = ThemeContext.useTheme()
	local snapshot = props.snapshot
	useTuningRevision()
	local path, setPath = React.useState("")
	local value, setValue = React.useState("")

	local children: { [string]: any } = {}

	children.Server = e(Controls.Section, { title = "Server flags", layoutOrder = 1 }, {
		List = e(FlagList, {
			flags = snapshot.lists.flags,
			error = snapshot.listErrors.flags,
			command = "flag",
			refresh = "flags",
			snapshot = snapshot,
		}),
	})
	children.Client = e(Controls.Section, { title = "Client flags", layoutOrder = 2 }, {
		List = e(FlagList, {
			flags = snapshot.lists.cflags,
			error = snapshot.listErrors.cflags,
			command = "cflag",
			refresh = "cflags",
			snapshot = snapshot,
		}),
	})

	-- Tuning overrides.
	local leaves = overrideLeaves()
	local overrideRows: { [string]: any } = {}
	for index, leaf in ipairs(leaves) do
		overrideRows[`o{index}`] = e(Controls.Row, { layoutOrder = index, height = Controls.ROW }, {
			Path = e(Controls.Label, {
				text = leaf.path,
				mono = true,
				size = Controls.MONO,
				height = Controls.ROW,
				width = UDim.new(0, 0),
				fill = true,
				layoutOrder = 1,
			}),
			Value = e(Controls.Label, {
				text = display(leaf.value),
				mono = true,
				size = Controls.MONO,
				height = Controls.ROW,
				autoWidth = true,
				color = theme.color.accent,
				layoutOrder = 2,
			}),
			Edit = e(Controls.Button, {
				text = "Edit",
				layoutOrder = 3,
				onActivated = function()
					setPath(leaf.path)
					setValue(display(leaf.value))
				end,
			}),
			Reset = e(Controls.Button, {
				text = "Reset",
				busy = snapshot.busy["tune:" .. leaf.path],
				layoutOrder = 4,
				onActivated = function()
					ConsoleStore.run(`tune reset {leaf.path}`, { key = "tune:" .. leaf.path })
				end,
			}),
		})
	end
	if #leaves == 0 then
		overrideRows.Empty = e(Controls.Label, {
			text = "No overrides: every Config value is at its default.",
			size = Controls.SMALL,
			color = theme.color.textMuted,
			layoutOrder = 0,
		})
	end

	-- Paths matching what is typed, with their current values.
	local suggestions: { [string]: any } = {}
	local exact = false
	if path ~= "" then
		local needle = string.lower(path)
		local shown = 0
		for _, candidate in ipairs(DevTuningService.listPaths()) do
			local lower = string.lower(candidate)
			if lower == needle then
				exact = true
			end
			if shown < MAX_PATH_SUGGESTIONS and lower ~= needle and string.find(lower, needle, 1, true) then
				shown += 1
				suggestions[`p{shown}`] = e("TextButton", {
					Text = "",
					Size = UDim2.new(1, 0, 0, 28),
					LayoutOrder = shown,
					BackgroundTransparency = 1,
					AutoButtonColor = false,
					[React.Event.Activated] = function()
						setPath(candidate)
						setValue(display(DevTuningService.get(candidate)))
					end,
					[React.Event.MouseEnter] = function(button: TextButton)
						button.BackgroundTransparency = 0.9
					end,
					[React.Event.MouseLeave] = function(button: TextButton)
						button.BackgroundTransparency = 1
					end,
					BackgroundColor3 = theme.color.accent,
				}, {
					Padding = Controls.padding(8),
					Path = e(Controls.Label, {
						text = candidate,
						mono = true,
						size = Controls.MONO,
						height = 28,
						width = UDim.new(0.7, 0),
					}),
					Value = e("Frame", { Size = UDim2.fromScale(0.3, 1), Position = UDim2.fromScale(0.7, 0), BackgroundTransparency = 1 }, {
						Text = e(Controls.Label, {
							text = display(DevTuningService.get(candidate)),
							mono = true,
							size = Controls.MONO,
							height = 28,
							alignX = Enum.TextXAlignment.Right,
							color = theme.color.textMuted,
						}),
					}),
				})
			end
		end
	end

	local tuneResult = snapshot.results.tune
	children.Tuning = e(Controls.Section, {
		title = "Tuning overrides",
		layoutOrder = 3,
		right = e(Controls.Button, {
			text = "Reset all",
			tone = "danger",
			enabled = #leaves > 0,
			busy = snapshot.busy["tune:all"],
			onActivated = function()
				ConsoleStore.run("tune reset", { key = "tune:all" })
			end,
		}),
	}, {
		List = e(Controls.Stack, { gap = 2, layoutOrder = 1 }, overrideRows),
		Path = e(Controls.LabelledRow, { label = "Path", labelWidth = 70, layoutOrder = 2 }, {
			Field = e(Controls.Field, {
				text = path,
				placeholder = "Camera.baseline.shoulderBack",
				mono = true,
				invalid = path ~= "" and not exact and next(suggestions) == nil,
				onChange = setPath,
				layoutOrder = 1,
			}),
		}),
		Suggestions = if next(suggestions)
			then e(Controls.Stack, { gap = 0, layoutOrder = 3 }, suggestions)
			else nil,
		Current = if exact
			then e(Controls.Label, {
				text = `now {display(DevTuningService.get(path))}`,
				mono = true,
				size = Controls.MONO,
				color = theme.color.textMuted,
				layoutOrder = 4,
			})
			else nil,
		Value = e(Controls.LabelledRow, { label = "Value", labelWidth = 70, layoutOrder = 5 }, {
			Field = e(Controls.Field, {
				text = value,
				placeholder = "number, true/false, or x, y, z",
				mono = true,
				fill = true,
				onChange = setValue,
				onSubmit = function()
					if path ~= "" and value ~= "" then
						ConsoleStore.run(`tune set {path} {value}`, { key = "tune" })
					end
				end,
				layoutOrder = 1,
			}),
			Set = e(Controls.Button, {
				text = "Set",
				tone = "primary",
				enabled = path ~= "" and value ~= "",
				busy = snapshot.busy.tune,
				layoutOrder = 2,
				onActivated = function()
					ConsoleStore.run(`tune set {path} {value}`, { key = "tune" })
				end,
			}),
		}),
		Result = e(Controls.ResultLine, { result = tuneResult, layoutOrder = 6 }),
	})

	return e(Controls.Stack, { gap = 14 }, children)
end

return DebugTab
