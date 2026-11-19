--!strict
-- Debug: server and client debug flags as two columns of switches, the client tuning overrides, a
-- line to set any tuning value, and the game's stat defaults editable for the session.
--
-- Flags are read with `flags` / `cflags` and flipped with `flag` / `cflag`; they are the selectable
-- rows, so Enter flips the selected one. Tuning is changed only through `tune set` / `tune reset`;
-- the override list and the path suggestions are read from DevTuningService directly, since asking
-- `tune` for them would print every path to the output.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Console = script.Parent.Parent
local ui = Console.Parent.Parent
local ConsoleStore = require(Console.ConsoleStore)
local Controls = require(Console.Controls)
local Selection = require(Console.Selection)
local Theme = require(Console.Theme)
local DevTuningService = require(ui.Parent.dev.DevTuningService)

local e = React.createElement
local size = Theme.size

local TAB = "debug"
local MAX_PATH_SUGGESTIONS = 8

local function sortedKeys(map: { [string]: any }?): { string }
	local keys: { string } = {}
	for key in pairs(map or {}) do
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

local function flagCommand(command: string, name: string, on: boolean): string
	return `{command} {name} {if on then "false" else "true"}`
end

local function FlagColumn(props: {
	title: string,
	flags: { [string]: boolean }?,
	error: string?,
	command: string,
	refresh: ConsoleStore.ListName,
	selectedKey: string?,
	snapshot: ConsoleStore.State,
	layoutOrder: number,
})
	local children: { [string]: any } = {
		Layout = Controls.list(Enum.FillDirection.Vertical, 0),
		Label = e(Controls.SectionLabel, { text = props.title, first = true, layoutOrder = 0 }),
	}
	if not props.flags then
		children.Empty = e(Controls.Empty, { text = props.error or "Reading flags…", bad = props.error ~= nil, layoutOrder = 1 })
	else
		for index, name in ipairs(sortedKeys(props.flags)) do
			local on = props.flags[name] == true
			local key = `{props.command}:{name}`
			children[`f{index}`] = e(Controls.Row, {
				title = name,
				mono = true,
				titleTone = if on then "text" else "secondary",
				selected = key == props.selectedKey,
				onSelect = function()
					ConsoleStore.pick(TAB, key)
				end,
				right = {
					Switch = e(Controls.Switch, {
						value = on,
						busy = props.snapshot.busy[key],
						onToggle = function()
							ConsoleStore.run(flagCommand(props.command, name, on), { key = key, refresh = { props.refresh } })
						end,
					}),
				},
				layoutOrder = index,
			})
		end
	end
	return e("Frame", {
		Size = UDim2.new(0.5, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
	}, children)
end

local EXPORT_KEY = "defaults:export"

local function shortNumber(value: any): string
	if type(value) ~= "number" then
		return tostring(value)
	end
	if value % 1 == 0 then
		return tostring(value)
	end
	return (string.gsub(string.format("%.4f", value), "%.?0+$", ""))
end

-- One default: name, the file's value and Reset when changed this session, the value to edit.
local function DefaultRow(props: { row: any, snapshot: ConsoleStore.State, layoutOrder: number })
	local row = props.row
	local key = `defaults:{row.stat}`
	local busy = props.snapshot.busy[key] == true
	local function run(command: string)
		ConsoleStore.clearResult(EXPORT_KEY)
		ConsoleStore.run(command, { key = key, refresh = { "defaults" } })
	end
	return e(Controls.Line, { layoutOrder = props.layoutOrder, gap = 8 }, {
		Name = e(Controls.Text, {
			text = row.stat,
			mono = true,
			size = size.monoSmall,
			tone = if row.changed then "warn" else "secondary",
			height = 28,
			fill = true,
			layoutOrder = 1,
		}),
		File = if row.changed
			then e(Controls.Text, {
				text = `file {shortNumber(row.file)}`,
				mono = true,
				size = size.monoSmall,
				tone = "dim",
				height = 28,
				autoWidth = true,
				layoutOrder = 2,
			})
			else nil,
		Reset = if row.changed
			then e(Controls.Button, {
				text = "Reset",
				busy = busy,
				layoutOrder = 3,
				onActivated = function()
					run(`defaults reset {row.stat}`)
				end,
			})
			else nil,
		Value = e(Controls.Field, {
			value = shortNumber(row.value),
			width = 84,
			alignX = Enum.TextXAlignment.Right,
			enabled = not busy,
			layoutOrder = 4,
			onCommit = function(text)
				local value = tonumber(text)
				if value and value ~= row.value then
					run(`defaults set {row.stat} {value}`)
				end
			end,
		}),
	})
end

-- The game's stat defaults (StatsConfig), editable for this session: `defaults`, `defaults set`,
-- `defaults reset`, `defaults export`.
local function GameDefaults(props: { snapshot: ConsoleStore.State, layoutOrder: number })
	local snapshot = props.snapshot
	local filter, setFilter = React.useState("")
	local data = snapshot.lists.defaults
	local rows: { any } = if data and data.defaults then data.defaults else {}
	local changed = if data then data.changed or 0 else 0

	local children: { [string]: any } = {
		Label = e(Controls.SectionLabel, {
			text = if data then `Game defaults · {#rows} · {changed} changed` else "Game defaults",
			layoutOrder = 1,
			right = {
				ResetAll = e(Controls.Button, {
					text = "Reset all",
					enabled = changed > 0,
					busy = snapshot.busy["defaults:all"],
					onActivated = function()
						ConsoleStore.clearResult(EXPORT_KEY)
						ConsoleStore.run("defaults reset", { key = "defaults:all", refresh = { "defaults" } })
					end,
				}),
			},
		}),
		Note = e(Controls.Stack, { pad = true, layoutOrder = 2 }, {
			Text = e(Controls.Text, {
				text = "Session only. A change applies now to new spawns and to every live entity that inherits the default, and is gone when Play stops. To keep it, Export and paste it into StatsConfig.luau.",
				tone = "secondary",
				size = size.secondary,
				wrap = true,
			}),
		}),
		Tools = e(Controls.Line, { layoutOrder = 3, gap = 6, vertical = 8 }, {
			Filter = e(Controls.Input, {
				text = filter,
				placeholder = "filter",
				mono = false,
				fill = true,
				onChange = setFilter,
				layoutOrder = 1,
			}),
			Export = e(Controls.Button, {
				text = "Export",
				enabled = changed > 0,
				busy = snapshot.busy[EXPORT_KEY],
				layoutOrder = 2,
				onActivated = function()
					ConsoleStore.run("defaults export", { key = EXPORT_KEY })
				end,
			}),
		}),
	}

	if not data then
		children.Empty = e(Controls.Empty, {
			text = snapshot.listErrors.defaults or "Reading defaults…",
			bad = snapshot.listErrors.defaults ~= nil,
			layoutOrder = 4,
		})
	else
		local needle = string.lower(filter)
		local shown = 0
		for _, row in ipairs(rows) do
			if needle == "" or string.find(string.lower(row.stat), needle, 1, true) then
				shown += 1
				children[`d{shown}`] = e(DefaultRow, { row = row, snapshot = snapshot, layoutOrder = 10 + shown })
			end
		end
		if shown == 0 then
			children.NoMatch = e(Controls.Empty, { text = "No default matches.", layoutOrder = 10 })
		end
	end

	local exported = snapshot.results[EXPORT_KEY]
	if exported then
		local luau = exported.data and exported.data.luau
		children.Export = e(Controls.Stack, { pad = true, gap = 6, layoutOrder = 200 }, {
			Head = e(Controls.Line, { inset = false, gap = 8, layoutOrder = 1 }, {
				Text = e(Controls.Text, {
					text = if type(luau) == "string" and luau ~= ""
						then "Replace these entries in StatsConfig.luau (select, Ctrl+A, Ctrl+C)"
						else exported.message,
					tone = if exported.ok then "secondary" else "bad",
					size = size.secondary,
					wrap = true,
					fill = true,
					layoutOrder = 1,
				}),
				Close = e(Controls.IconButton, {
					glyph = "close",
					layoutOrder = 2,
					onActivated = function()
						ConsoleStore.clearResult(EXPORT_KEY)
					end,
				}),
			}),
			Code = if type(luau) == "string" and luau ~= ""
				then e(Controls.CodeView, { text = luau, height = 260, layoutOrder = 2 })
				else nil,
		})
	end

	return e(Controls.Stack, { layoutOrder = props.layoutOrder }, children)
end

local function DebugTab(props: { snapshot: ConsoleStore.State })
	local snapshot = props.snapshot
	useTuningRevision()
	local path, setPath = React.useState("")
	local value, setValue = React.useState("")

	local serverFlags: { [string]: boolean }? = snapshot.lists.flags
	local clientFlags: { [string]: boolean }? = snapshot.lists.cflags

	local keys: { string } = {}
	for _, name in ipairs(sortedKeys(serverFlags)) do
		table.insert(keys, "flag:" .. name)
	end
	for _, name in ipairs(sortedKeys(clientFlags)) do
		table.insert(keys, "cflag:" .. name)
	end
	local selectedKey = Selection.resolve(snapshot, TAB, keys)

	local primary: ConsoleStore.Primary? = nil
	if selectedKey then
		local command, name = string.match(selectedKey, "^(%w+):(.+)$")
		if command and name then
			local flags = if command == "flag" then serverFlags else clientFlags
			local on = flags ~= nil and flags[name] == true
			primary = {
				label = if on then "Turn off" else "Turn on",
				command = flagCommand(command, name, on),
				options = { key = selectedKey, refresh = { if command == "flag" then "flags" else "cflags" } },
			}
		end
	end
	Selection.usePublish(TAB, { keys = keys, selected = selectedKey, primary = primary })

	local children: { [string]: any } = {}

	children.Flags = e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 1,
	}, {
		Layout = Controls.list(Enum.FillDirection.Horizontal, 0, { VerticalAlignment = Enum.VerticalAlignment.Top }),
		Server = e(FlagColumn, {
			title = "Server flags",
			flags = serverFlags,
			error = snapshot.listErrors.flags,
			command = "flag",
			refresh = "flags",
			selectedKey = selectedKey,
			snapshot = snapshot,
			layoutOrder = 1,
		}),
		Client = e(FlagColumn, {
			title = "Client flags",
			flags = clientFlags,
			error = snapshot.listErrors.cflags,
			command = "cflag",
			refresh = "cflags",
			selectedKey = selectedKey,
			snapshot = snapshot,
			layoutOrder = 2,
		}),
	})

	-- Tuning overrides.
	local leaves = overrideLeaves()
	children.TuningLabel = e(Controls.SectionLabel, {
		text = `Tuning overrides · {#leaves}`,
		layoutOrder = 10,
		right = {
			Reset = e(Controls.Button, {
				text = "Reset all",
				enabled = #leaves > 0,
				busy = snapshot.busy["tune:all"],
				onActivated = function()
					ConsoleStore.run("tune reset", { key = "tune:all" })
				end,
			}),
		},
	})
	for index, leaf in ipairs(leaves) do
		children[`o{index}`] = e(Controls.Line, { layoutOrder = 10 + index, gap = 8 }, {
			Path = e(Controls.Text, { text = leaf.path, mono = true, size = size.monoSmall, height = 28, fill = true, layoutOrder = 1 }),
			Value = e(Controls.Text, { text = display(leaf.value), mono = true, size = size.monoSmall, height = 28, autoWidth = true, layoutOrder = 2 }),
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
		children.TuningEmpty = e(Controls.Empty, { text = "None: every Config value is at its default.", layoutOrder = 11 })
	end

	-- Set a value: the path, matching paths with their current values, the value.
	local exact = false
	local matches: { string } = {}
	if path ~= "" then
		local needle = string.lower(path)
		for _, candidate in ipairs(DevTuningService.listPaths()) do
			local lower = string.lower(candidate)
			if lower == needle then
				exact = true
			elseif #matches < MAX_PATH_SUGGESTIONS and string.find(lower, needle, 1, true) then
				table.insert(matches, candidate)
			end
		end
	end
	local function set()
		if path ~= "" and value ~= "" then
			ConsoleStore.run(`tune set {path} {value}`, { key = "tune" })
		end
	end
	children.SetLabel = e(Controls.SectionLabel, {
		text = if exact then `Set a value · now {display(DevTuningService.get(path))}` else "Set a value",
		layoutOrder = 200,
	})
	children.Set = e(Controls.Line, { layoutOrder = 201, gap = 6 }, {
		Path = e(Controls.Input, {
			text = path,
			placeholder = "Camera.baseline.fov",
			fill = true,
			invalid = path ~= "" and not exact and #matches == 0,
			onChange = setPath,
			layoutOrder = 1,
		}),
		Value = e(Controls.Input, {
			text = value,
			placeholder = "value",
			width = 90,
			onChange = setValue,
			onSubmit = set,
			layoutOrder = 2,
		}),
		Set = e(Controls.Button, {
			text = "Set",
			enabled = path ~= "" and value ~= "",
			busy = snapshot.busy.tune,
			layoutOrder = 3,
			onActivated = set,
		}),
	})
	for index, candidate in ipairs(matches) do
		children[`p{index}`] = e(Controls.Row, {
			title = candidate,
			mono = true,
			titleTone = "secondary",
			onSelect = function()
				setPath(candidate)
				setValue(display(DevTuningService.get(candidate)))
			end,
			right = {
				Value = e(Controls.Text, {
					text = display(DevTuningService.get(candidate)),
					mono = true,
					size = size.monoSmall,
					tone = "dim",
					height = 34,
					autoWidth = true,
				}),
			},
			layoutOrder = 201 + index,
		})
	end
	if path == "" then
		children.SetHint = e(Controls.Empty, { text = "Number, true/false, or x, y, z. Type part of a path to find it.", layoutOrder = 220 })
	end
	if snapshot.results.tune then
		children.Result = e(Controls.Stack, { pad = true, layoutOrder = 230 }, {
			Line = e(Controls.Result, { result = snapshot.results.tune }),
		})
	end

	children.Defaults = e(GameDefaults, { snapshot = snapshot, layoutOrder = 300 })

	return e(Controls.TabLayout, {}, children)
end

return DebugTab
