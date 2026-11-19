--!strict
-- Log: two lists. Commands is what the console ran, newest first -- typed or clicked -- with the
-- result and the time. Output is the client's own warnings and errors (the ones the edge badge counts
-- while the console is closed). Failures and errors carry a red edge so a scan down the list finds
-- them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Console = script.Parent.Parent
local ThemeContext = require(Console.Parent.Parent.hooks.ThemeContext)
local ConsoleStore = require(Console.ConsoleStore)
local Controls = require(Console.Controls)

local client = script:FindFirstAncestor("Client") :: Instance
local DevCommandsClient = require((client :: any).dev.Commands)

local e = React.createElement

-- Drawn at once; older entries stay in their lists (up to each list's own limit) but are not drawn.
local SHOWN = 80

local function useCommandLog(): ({ any }, (any) -> ())
	local entries, setEntries = React.useState(DevCommandsClient.getLog)
	React.useEffect(function()
		local stop = DevCommandsClient.onLog(function()
			setEntries(DevCommandsClient.getLog())
		end)
		setEntries(DevCommandsClient.getLog())
		return stop
	end, {})
	return entries, setEntries
end

local function Entry(props: {
	time: number,
	text: string?,
	message: string,
	ok: boolean,
	-- A warning: amber, without the failure edge.
	warning: boolean?,
	layoutOrder: number,
})
	local theme = ThemeContext.useTheme()
	local color = if props.warning then theme.color.critical elseif props.ok then theme.color.success else theme.color.danger
	return e(Controls.Card, { layoutOrder = props.layoutOrder, alert = not props.ok and not props.warning }, {
		Top = e(Controls.Row, { layoutOrder = 1, gap = 10 }, {
			Time = e(Controls.Label, {
				text = os.date("%H:%M:%S", props.time) :: string,
				mono = true,
				size = Controls.MONO,
				height = 24,
				autoWidth = true,
				color = theme.color.textMuted,
				layoutOrder = 1,
			}),
			Text = if props.text
				then e(Controls.Label, {
					text = "› " .. props.text,
					mono = true,
					size = Controls.MONO,
					height = 24,
					width = UDim.new(0, 0),
					fill = true,
					layoutOrder = 2,
				})
				else nil,
		}),
		Message = e(Controls.Label, {
			text = props.message,
			size = Controls.SMALL,
			bold = not props.ok and not props.warning,
			wrap = true,
			color = color,
			layoutOrder = 2,
		}),
	})
end

local function LogTab(props: { snapshot: ConsoleStore.State })
	local theme = ThemeContext.useTheme()
	local snapshot = props.snapshot
	local entries, setEntries = useCommandLog()
	local failuresOnly, setFailuresOnly = React.useState(false)
	local view = snapshot.logView

	local failures = 0
	for _, entry in ipairs(entries) do
		if not entry.result.ok then
			failures += 1
		end
	end
	local errors = 0
	for _, entry in ipairs(snapshot.output) do
		if entry.isError then
			errors += 1
		end
	end

	local rows: { [string]: any } = {}
	local shown = 0
	if view == "output" then
		for index = #snapshot.output, 1, -1 do
			if shown >= SHOWN then
				break
			end
			local entry = snapshot.output[index]
			if not failuresOnly or entry.isError then
				shown += 1
				rows[`o{index}`] = e(Entry, {
					time = entry.time,
					message = entry.message,
					ok = false,
					warning = not entry.isError,
					layoutOrder = shown,
				})
			end
		end
	else
		for index = #entries, 1, -1 do
			if shown >= SHOWN then
				break
			end
			local entry = entries[index]
			if not failuresOnly or not entry.result.ok then
				shown += 1
				rows[`e{index}`] = e(Entry, {
					time = entry.time,
					text = entry.text,
					message = entry.result.message,
					ok = entry.result.ok,
					layoutOrder = shown,
				})
			end
		end
	end
	if shown == 0 then
		rows.Empty = e(Controls.Label, {
			text = if view == "output"
				then "No client warnings or errors."
				elseif failuresOnly then "No failures."
				else "Nothing run yet.",
			color = theme.color.textMuted,
			layoutOrder = 0,
		})
	end

	return e(Controls.Stack, { gap = 10 }, {
		Views = e(Controls.Row, { layoutOrder = 0 }, {
			Commands = e(Controls.Button, {
				text = `Commands {#entries}`,
				selected = view ~= "output",
				layoutOrder = 1,
				onActivated = function()
					ConsoleStore.setLogView("commands")
				end,
			}),
			Output = e(Controls.Button, {
				text = `Output {#snapshot.output}`,
				selected = view == "output",
				layoutOrder = 2,
				onActivated = function()
					ConsoleStore.setLogView("output")
				end,
			}),
		}),
		Bar = e(Controls.Row, { layoutOrder = 1 }, {
			Count = e(Controls.Label, {
				text = if view == "output" then `{#snapshot.output - errors} warnings · {errors} errors` else `{failures} failed`,
				bold = true,
				height = Controls.ROW,
				width = UDim.new(0, 0),
				fill = true,
				color = if (view == "output" and errors > 0) or (view ~= "output" and failures > 0)
					then theme.color.danger
					else theme.color.textMuted,
				layoutOrder = 1,
			}),
			Failures = e(Controls.Button, {
				text = if view == "output" then "Errors only" else "Failures only",
				selected = failuresOnly,
				layoutOrder = 2,
				onActivated = function()
					setFailuresOnly(not failuresOnly)
				end,
			}),
			Clear = e(Controls.Button, {
				text = "Clear",
				tone = "danger",
				enabled = if view == "output" then #snapshot.output > 0 else #entries > 0,
				layoutOrder = 3,
				onActivated = function()
					if view == "output" then
						ConsoleStore.clearOutput()
					else
						DevCommandsClient.clearLog()
						setEntries({})
					end
				end,
			}),
		}),
		List = e(Controls.Stack, { gap = 6, layoutOrder = 2 }, rows),
	})
end

return LogTab
