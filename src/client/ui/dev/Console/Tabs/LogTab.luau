--!strict
-- Log: two lists behind one switch. Commands is what the console ran, newest first -- typed or
-- clicked -- with the time and the result in green or red; a picked entry can be run again with
-- Enter. Output is the client's own warnings and errors (the ones the edge badge counts while the
-- console is closed).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local Console = script.Parent.Parent
local ConsoleStore = require(Console.ConsoleStore)
local Controls = require(Console.Controls)
local Selection = require(Console.Selection)
local Theme = require(Console.Theme)

local client = script:FindFirstAncestor("Client") :: Instance
local DevCommandsClient = require((client :: any).dev.Commands)

local e = React.createElement
local color = Theme.color
local size = Theme.size
local space = Theme.space

local TAB = "log"
-- Drawn at once; older entries stay in their lists (up to each list's own limit) but are not drawn.
local SHOWN = 80
local TIME_WIDTH = 70

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
	tone: Controls.Tone,
	selected: boolean?,
	onSelect: (() -> ())?,
	layoutOrder: number,
})
	local hovered, setHovered = React.useState(false)
	local ref = React.useRef(nil :: GuiObject?)
	React.useEffect(function()
		local object = ref.current
		local scroller = object and object:FindFirstAncestorWhichIsA("ScrollingFrame")
		if props.selected and object and scroller then
			local top = object.AbsolutePosition.Y - scroller.AbsolutePosition.Y
			local bottom = top + object.AbsoluteSize.Y
			local canvas = scroller.CanvasPosition
			if top < 0 then
				scroller.CanvasPosition = Vector2.new(canvas.X, math.max(0, canvas.Y + top - 8))
			elseif bottom > scroller.AbsoluteWindowSize.Y then
				scroller.CanvasPosition = Vector2.new(canvas.X, canvas.Y + bottom - scroller.AbsoluteWindowSize.Y + 8)
			end
		end
	end, { props.selected } :: { any })

	local time = os.date("%H:%M:%S", props.time) :: string
	return e("TextButton", {
		ref = ref,
		Text = "",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = props.layoutOrder,
		BackgroundColor3 = if props.selected then color.selected else color.hover,
		BackgroundTransparency = if props.selected then 0 elseif hovered and props.onSelect then 0.55 else 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Active = props.onSelect ~= nil,
		[React.Event.Activated] = function()
			if props.onSelect then
				props.onSelect()
			end
		end,
		[React.Event.MouseEnter] = function()
			setHovered(true)
		end,
		[React.Event.MouseLeave] = function()
			setHovered(false)
		end,
	}, {
		Mark = if props.selected
			then e("Frame", { Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = color.strongOutline, BorderSizePixel = 0 })
			else nil,
		Body = e("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
		}, {
			Padding = Controls.padding(space.pad, 6),
			Layout = Controls.list(Enum.FillDirection.Vertical, 1),
			Top = e("Frame", {
				Size = UDim2.new(1, 0, 0, 22),
				BackgroundTransparency = 1,
				LayoutOrder = 1,
			}, {
				Layout = Controls.list(Enum.FillDirection.Horizontal, space.gap),
				Time = e(Controls.Text, {
					text = time,
					mono = true,
					size = size.monoSmall,
					tone = "dim",
					height = 22,
					width = UDim.new(0, TIME_WIDTH),
					layoutOrder = 1,
				}),
				Text = if props.text
					then e(Controls.Text, { text = props.text, mono = true, size = size.monoSmall, height = 22, fill = true, layoutOrder = 2 })
					else e(Controls.Text, {
						text = if props.tone == "bad" then "error" else "warning",
						size = size.secondary,
						tone = props.tone,
						height = 22,
						fill = true,
						layoutOrder = 2,
					}),
			}),
			Message = e("Frame", {
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				LayoutOrder = 2,
			}, {
				Padding = e("UIPadding", { PaddingLeft = UDim.new(0, TIME_WIDTH + space.gap) }),
				Text = e(Controls.Text, {
					text = props.message,
					-- An output entry's first line already says error or warning in colour, so its text reads
					-- in plain ink.
					tone = if props.text then props.tone else "secondary",
					size = size.secondary,
					wrap = true,
				}),
			}),
		}),
	})
end

local function LogTab(props: { snapshot: ConsoleStore.State })
	local snapshot = props.snapshot
	local entries, setEntries = useCommandLog()
	local failuresOnly, setFailuresOnly = React.useState(false)
	local view = snapshot.logView
	local output = view == "output"

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

	-- Entries shown, newest first.
	local shown: { any } = {}
	if output then
		for index = #snapshot.output, 1, -1 do
			local entry = snapshot.output[index]
			if #shown < SHOWN and (not failuresOnly or entry.isError) then
				table.insert(shown, { key = `o{index}`, entry = entry })
			end
		end
	else
		for index = #entries, 1, -1 do
			local entry = entries[index]
			if #shown < SHOWN and (not failuresOnly or not entry.result.ok) then
				table.insert(shown, { key = `e{index}`, entry = entry })
			end
		end
	end

	local keys: { string } = {}
	if not output then
		for _, item in ipairs(shown) do
			table.insert(keys, item.key)
		end
	end
	local selectedKey = Selection.resolve(snapshot, TAB, keys, nil, true)
	local primary: ConsoleStore.Primary? = nil
	for _, item in ipairs(shown) do
		if item.key == selectedKey then
			primary = { label = "Run again", command = item.entry.text, options = { refresh = ConsoleStore.ALL_LISTS } }
		end
	end
	Selection.usePublish(TAB, { keys = keys, selected = selectedKey, primary = primary })

	local children: { [string]: any } = {}
	for order, item in ipairs(shown) do
		local entry = item.entry
		if output then
			children[item.key] = e(Entry, {
				time = entry.time,
				message = entry.message,
				tone = if entry.isError then "bad" else "warn",
				layoutOrder = order,
			})
		else
			children[item.key] = e(Entry, {
				time = entry.time,
				text = entry.text,
				message = entry.result.message,
				tone = if entry.result.ok then "ok" else "bad",
				selected = item.key == selectedKey,
				onSelect = function()
					ConsoleStore.pick(TAB, item.key)
				end,
				layoutOrder = order,
			})
		end
	end
	if #shown == 0 then
		children.Empty = e(Controls.Empty, {
			text = if output then "No client warnings or errors." elseif failuresOnly then "No failures." else "Nothing run yet.",
			layoutOrder = 0,
		})
	end

	local bad = if output then errors else failures
	local top = e(Controls.Line, { vertical = 8, gap = 6 }, {
		Commands = e(Controls.Chip, {
			text = `Commands · {#entries}`,
			selected = not output,
			layoutOrder = 1,
			onActivated = function()
				ConsoleStore.setLogView("commands")
			end,
		}),
		Output = e(Controls.Chip, {
			text = `Output · {#snapshot.output}`,
			selected = output,
			layoutOrder = 2,
			onActivated = function()
				ConsoleStore.setLogView("output")
			end,
		}),
		Spacer = e(Controls.Spacer, { layoutOrder = 3 }),
		-- The failure count doubles as the filter for it, red while there is anything to find.
		Failures = e(Controls.Chip, {
			text = `{if output then "Errors" else "Failed"} · {bad}`,
			tone = if bad > 0 and not failuresOnly then "bad" else nil,
			selected = failuresOnly,
			layoutOrder = 4,
			onActivated = function()
				setFailuresOnly(not failuresOnly)
			end,
		}),
		Clear = e(Controls.Button, {
			text = "Clear",
			enabled = if output then #snapshot.output > 0 else #entries > 0,
			layoutOrder = 5,
			onActivated = function()
				if output then
					ConsoleStore.clearOutput()
				else
					DevCommandsClient.clearLog()
					setEntries({})
				end
			end,
		}),
	})

	return e(Controls.TabLayout, { top = top }, children)
end

return LogTab
