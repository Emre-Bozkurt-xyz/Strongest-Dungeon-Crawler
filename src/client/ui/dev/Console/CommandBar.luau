--!strict
-- The command line at the head of the console, the main way in: a search-style input, the
-- suggestions dropping under it, and one line below for the usage of the command being typed or the
-- last result.
--
-- Keys while it has focus:
--   Tab        takes the first suggestion; on an empty line, takes the ghost command to edit.
--   Up/Down    on an empty line, move the selection in the tab's list; with text on the line (or
--              once walking it), walk the history. Ctrl+Up/Down walk the history from anywhere.
--   Enter      runs the line and keeps focus. On an empty line it runs the selected row's primary
--              action, whose command is shown as ghost text meanwhile, so the UI teaches the
--              commands it runs.
--
-- The result shown is the last thing the console ran, typed or clicked, so a button's failure is as
-- visible as a typed command's.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local React = require(ReplicatedStorage.Packages.React)
local ConsoleStore = require(script.Parent.ConsoleStore)
local Controls = require(script.Parent.Controls)
local Autocomplete = require(script.Parent.Autocomplete)
local Glyphs = require(script.Parent.Glyphs)
local Theme = require(script.Parent.Theme)

local e = React.createElement
local color = Theme.color
local size = Theme.size

local INPUT_HEIGHT = 42
local SUGGESTION_ROW = 32
-- Result text is clipped to this height and scrolls; the Log tab has it in full.
local INFO_MAX_HEIGHT = 84
local INFO_MIN_HEIGHT = 46
local INFO_LINES = 2

local function merge(into: { [string]: any }, from: { [string]: any }): { [string]: any }
	for key, value in pairs(from) do
		into[key] = value
	end
	return into
end

local function escape(text: string): string
	return (string.gsub(string.gsub(string.gsub(text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

-- The usage line with the argument being typed lit, so it is clear what goes next.
local function usageText(descriptor: any, argIndex: number?): string
	local bright = color.text:ToHex()
	local parts = { `<font color="#{bright}">{escape(descriptor.name)}</font>` }
	for index, arg in ipairs(descriptor.args or {}) do
		local text = escape(Autocomplete.describeArg(arg))
		if index == argIndex then
			text = `<font color="#{bright}"><u>{text}</u></font>`
		end
		table.insert(parts, text)
	end
	return table.concat(parts, " ")
end

local function ctrlHeld(): boolean
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
end

local function Suggestion(props: { suggestion: Autocomplete.Suggestion, first: boolean, layoutOrder: number, onPick: () -> () })
	local hovered, setHovered = React.useState(false)
	local suggestion = props.suggestion
	return e("TextButton", {
		Text = "",
		Size = UDim2.new(1, 0, 0, SUGGESTION_ROW),
		LayoutOrder = props.layoutOrder,
		BackgroundColor3 = color.suggestion,
		BackgroundTransparency = if props.first or hovered then 0 else 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		ZIndex = 31,
		[React.Event.Activated] = props.onPick,
		[React.Event.MouseEnter] = function()
			setHovered(true)
		end,
		[React.Event.MouseLeave] = function()
			setHovered(false)
		end,
	}, {
		Corner = Controls.corner(),
		Padding = Controls.padding(10),
		Layout = Controls.list(Enum.FillDirection.Horizontal, 10),
		Name = e(Controls.Text, {
			text = suggestion.label,
			mono = true,
			size = size.mono,
			height = SUGGESTION_ROW,
			autoWidth = true,
			zIndex = 31,
			layoutOrder = 1,
		}),
		Detail = e(Controls.Text, {
			text = suggestion.detail or "",
			tone = "secondary",
			size = size.secondary,
			height = SUGGESTION_ROW,
			fill = true,
			alignX = Enum.TextXAlignment.Right,
			zIndex = 31,
			layoutOrder = 2,
		}),
		Tab = if props.first then e(Controls.Kbd, { text = "Tab", zIndex = 31, layoutOrder = 3 }) else nil,
	})
end

local function CommandBar(props: { snapshot: ConsoleStore.State, layoutOrder: number? })
	local snapshot = props.snapshot
	local text, setText = React.useState("")
	local focused, setFocused = React.useState(false)
	local boxRef = React.useRef(nil :: TextBox?)
	-- Position in the history while walking it; nil when editing a fresh line.
	local historyIndex = React.useRef(nil :: number?)
	-- What was being typed before walking the history, given back on walking past its end.
	local draft = React.useRef("")
	local cursorToEnd, setCursorToEnd = React.useState(0)

	local analysis = Autocomplete.analyze(text, snapshot.descriptors)
	local suggestions = if focused then analysis.suggestions else {}
	local ghost = snapshot.ghosts[snapshot.tab]

	-- The key handler outlives renders, so it reads the latest line, suggestions and ghost through a ref.
	local latest = React.useRef({ text = text, suggestions = suggestions, ghost = ghost })
	latest.current = { text = text, suggestions = suggestions, ghost = ghost }

	local function replaceLine(line: string)
		setText(line)
		setCursorToEnd(function(n)
			return n + 1
		end)
	end

	React.useEffect(function()
		local box = boxRef.current
		if box and cursorToEnd > 0 then
			box.CursorPosition = #box.Text + 1
		end
	end, { cursorToEnd })

	local function refocus()
		-- FocusLost has already run; take focus back on the next frame so typing can continue.
		task.defer(function()
			if boxRef.current and ConsoleStore.get().open then
				boxRef.current:CaptureFocus()
			end
		end)
	end

	local function submit(line: string)
		local trimmed = string.match(line, "^%s*(.-)%s*$") :: string
		historyIndex.current = nil
		draft.current = ""
		setText("")
		-- Cleared on the box as well: when Enter follows the last keystroke within a frame, the state
		-- may not hold that text yet, so clearing it alone would change nothing and leave the line up.
		if boxRef.current then
			boxRef.current.Text = ""
		end
		if trimmed ~= "" then
			ConsoleStore.run(trimmed, { typed = true, refresh = ConsoleStore.ALL_LISTS })
		else
			local _, fill = ConsoleStore.runPrimary()
			if fill then
				replaceLine(fill)
			end
		end
		refocus()
	end

	React.useEffect(function()
		ConsoleStore.setFocuser(function()
			local box = boxRef.current
			local focusedBox = UserInputService:GetFocusedTextBox()
			if box and ConsoleStore.get().open and (focusedBox == nil or focusedBox == box) then
				box:CaptureFocus()
			end
		end)
		return function()
			ConsoleStore.setFocuser(nil)
		end
	end, {})

	-- The line is the way in, so it has the keyboard whenever the console opens.
	React.useEffect(function()
		if snapshot.open then
			task.defer(function()
				if boxRef.current and ConsoleStore.get().open and UserInputService:GetFocusedTextBox() == nil then
					boxRef.current:CaptureFocus()
				end
			end)
		end
	end, { snapshot.open })

	React.useEffect(function()
		local function walkHistory(up: boolean)
			local history = ConsoleStore.history()
			if #history == 0 then
				return
			end
			local index = historyIndex.current
			if up then
				if index == nil then
					draft.current = latest.current.text
					index = #history
				else
					index = math.max(1, index - 1)
				end
			else
				if index == nil then
					return
				end
				index += 1
				if index > #history then
					historyIndex.current = nil
					replaceLine(draft.current)
					return
				end
			end
			historyIndex.current = index
			replaceLine(history[index])
		end

		local connection = UserInputService.InputBegan:Connect(function(input)
			local box = boxRef.current
			if not box or UserInputService:GetFocusedTextBox() ~= box then
				return
			end
			if input.KeyCode == Enum.KeyCode.Tab then
				local first = latest.current.suggestions[1]
				local current = latest.current
				if first then
					replaceLine(first.line)
				elseif current.text == "" and current.ghost then
					replaceLine(current.ghost.command)
				end
			elseif input.KeyCode == Enum.KeyCode.Up or input.KeyCode == Enum.KeyCode.Down then
				local up = input.KeyCode == Enum.KeyCode.Up
				local onSelection = latest.current.text == "" and historyIndex.current == nil and not ctrlHeld()
				if onSelection and ConsoleStore.moveSelection(if up then -1 else 1) then
					return
				end
				walkHistory(up)
			end
		end)
		return function()
			connection:Disconnect()
		end
	end, {})

	-- The suggestions, dropping over the content under the input.
	local rows: { [string]: any } = {
		Layout = Controls.list(Enum.FillDirection.Vertical, 2),
		Padding = Controls.padding(4, 4),
	}
	for index, suggestion in ipairs(suggestions) do
		rows[`s{index}`] = e(Suggestion, {
			suggestion = suggestion,
			first = index == 1,
			layoutOrder = index,
			onPick = function()
				replaceLine(suggestion.line)
				if boxRef.current then
					boxRef.current:CaptureFocus()
				end
			end,
		})
	end

	-- Under the input: the usage of the command being typed, else the last result, else the keys.
	local info: any
	local last = snapshot.last
	if analysis.descriptor then
		info = e(Controls.Text, {
			text = usageText(analysis.descriptor, analysis.argIndex)
				.. `  <font color="#{color.dim:ToHex()}">{escape(analysis.descriptor.summary)}</font>`,
			richText = true,
			mono = true,
			size = size.monoSmall,
			tone = "secondary",
			wrap = true,
		})
	elseif last then
		-- A long answer (a preset's source, a list) is cut to its first lines here; the Log has it whole.
		local lines = string.split(last.message, "\n")
		local message = last.message
		if #lines > INFO_LINES then
			message = table.concat(lines, "\n", 1, INFO_LINES) .. `\n… {#lines - INFO_LINES} more lines in the Log`
		end
		last = { text = last.text, ok = last.ok, message = message, time = last.time }
		info = e("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
		}, {
			Layout = Controls.list(Enum.FillDirection.Vertical, 1),
			Ran = e(Controls.Text, { text = "› " .. last.text, mono = true, size = size.monoSmall, tone = "dim", layoutOrder = 1 }),
			Message = e(Controls.Result, { result = last, layoutOrder = 2 }),
		})
	else
		local parts: { [string]: any } = {}
		for index, part in ipairs({ { "↑↓", "pick a row" }, { Controls.ENTER, "run it" }, { "Tab", "complete" }, { "Ctrl ↑", "history" } }) do
			parts[`k{index}`] = e(Controls.Kbd, { text = part[1], layoutOrder = index * 2 - 1 })
			parts[`t{index}`] = e(Controls.Text, {
				text = part[2],
				tone = "dim",
				size = size.secondary,
				height = 22,
				autoWidth = true,
				layoutOrder = index * 2,
			})
		end
		info = e(Controls.Line, { inset = false, vertical = 0, gap = 6, wrap = true }, parts)
	end

	local placeholder = if ghost then ghost.command else "Run a command  (help lists them)"
	local hint = if text ~= "" then nil elseif ghost then ghost.label else nil

	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
		ZIndex = 20,
	}, {
		Padding = Controls.padding(12, nil, 12, 8),
		Layout = Controls.list(Enum.FillDirection.Vertical, 8),
		Input = e("Frame", {
			Size = UDim2.new(1, 0, 0, INPUT_HEIGHT),
			BackgroundColor3 = color.raised,
			BorderSizePixel = 0,
			LayoutOrder = 1,
			-- Above the info line and the content, which the suggestions open over.
			ZIndex = 30,
		}, {
			Corner = Controls.corner(Theme.radius.large),
			Stroke = Controls.outline(if focused then color.strongOutline else color.outline),
			Prompt = e(Glyphs.Glyph, {
				name = "search",
				color = if focused then color.secondary else color.dim,
				size = 16,
				position = UDim2.new(0, 14, 0.5, 0),
				anchorPoint = Vector2.new(0, 0.5),
			}),
			Box = e("TextBox", {
				ref = boxRef,
				Text = text,
				PlaceholderText = placeholder,
				PlaceholderColor3 = color.dim,
				Size = UDim2.new(1, -(40 + 110), 1, 0),
				Position = UDim2.fromOffset(40, 0),
				BackgroundTransparency = 1,
				ClearTextOnFocus = false,
				FontFace = Theme.font.mono,
				TextSize = size.mono + 1,
				TextColor3 = color.text,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.None,
				ClipsDescendants = true,
				ZIndex = 30,
				[React.Change.Text] = function(box: TextBox)
					-- Tab and the console's own toggle key reach the box as characters; neither belongs in
					-- a command.
					local cleaned = string.gsub(string.gsub(box.Text, "\t", ""), "`", "")
					if cleaned ~= box.Text then
						box.Text = cleaned
						return
					end
					if cleaned ~= latest.current.text then
						historyIndex.current = nil
						setText(cleaned)
					end
				end,
				[React.Event.Focused] = function()
					setFocused(true)
				end,
				[React.Event.FocusLost] = function(box: TextBox, enterPressed: boolean)
					setFocused(false)
					if enterPressed then
						submit(box.Text)
					end
				end,
			}),
			Hint = e("Frame", {
				Size = UDim2.new(0, 104, 1, 0),
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -10, 0, 0),
				BackgroundTransparency = 1,
				ZIndex = 30,
			}, {
				Layout = Controls.list(Enum.FillDirection.Horizontal, 6, { HorizontalAlignment = Enum.HorizontalAlignment.Right }),
				Label = if hint
					then e(Controls.Text, { text = hint, tone = "dim", size = size.secondary, height = 20, autoWidth = true, zIndex = 30, layoutOrder = 1 })
					else nil,
				Key = e(Controls.Kbd, { text = Controls.ENTER, zIndex = 30, layoutOrder = 2 }),
			}),
			Suggestions = if #suggestions > 0
				then e("Frame", {
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					Position = UDim2.new(0, 0, 1, 4),
					BackgroundColor3 = color.panel,
					BorderSizePixel = 0,
					ZIndex = 31,
				}, merge({
					Corner = Controls.corner(Theme.radius.large),
					Stroke = Controls.outline(color.outline),
				}, rows))
				else nil,
		}),
		Info = e("ScrollingFrame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 2,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(),
			ScrollBarThickness = 4,
			ScrollBarImageColor3 = color.strongOutline,
			VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
		}, {
			-- At least two lines tall, so a one-line result arriving or the usage of a command being typed
			-- never moves the rail and rows under the cursor.
			Cap = e("UISizeConstraint", { MinSize = Vector2.new(0, INFO_MIN_HEIGHT), MaxSize = Vector2.new(math.huge, INFO_MAX_HEIGHT) }),
			Padding = Controls.padding(4),
			Content = info,
		}),
	})
end

return CommandBar
