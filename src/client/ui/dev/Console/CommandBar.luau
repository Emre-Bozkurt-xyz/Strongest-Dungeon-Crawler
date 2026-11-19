--!strict
-- The command line at the foot of the console, on every tab: the last result, a hint for the command
-- being typed, the suggestions, and the input.
--
-- Tab takes the first suggestion, Up and Down walk the history, Enter runs the line and keeps focus
-- so the next command can be typed straight away. The result shown is the last thing the console ran,
-- typed or clicked, so a button's failure is as visible as a typed command's.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local React = require(ReplicatedStorage.Packages.React)
local ThemeContext = require(script.Parent.Parent.Parent.hooks.ThemeContext)
local ConsoleStore = require(script.Parent.ConsoleStore)
local Controls = require(script.Parent.Controls)
local Autocomplete = require(script.Parent.Autocomplete)

local e = React.createElement

-- Result text is clipped to this height and scrolls; the Log tab has it in full.
local RESULT_MAX_HEIGHT = 92
local SUGGESTION_ROW = 28

local function escape(text: string): string
	return (string.gsub(string.gsub(text, "&", "&amp;"), "<", "&lt;"))
end

-- The usage line with the argument being typed lit, so it is clear what goes next.
local function hintText(descriptor: any, argIndex: number?, accent: Color3): string
	local parts = { `<b>{escape(descriptor.name)}</b>` }
	for index, arg in ipairs(descriptor.args or {}) do
		local text = escape(Autocomplete.describeArg(arg))
		if index == argIndex then
			text = `<font color="#{accent:ToHex()}"><b>{text}</b></font>`
		end
		table.insert(parts, text)
	end
	return table.concat(parts, " ")
end

local function CommandBar(props: { snapshot: ConsoleStore.State, layoutOrder: number? })
	local theme = ThemeContext.useTheme()
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

	-- The key handler outlives renders, so it reads the latest line and suggestions through a ref.
	local latest = React.useRef({ text = text, suggestions = suggestions })
	latest.current = { text = text, suggestions = suggestions }

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

	local function submit(line: string)
		local trimmed = string.match(line, "^%s*(.-)%s*$") :: string
		historyIndex.current = nil
		draft.current = ""
		setText("")
		if trimmed ~= "" then
			ConsoleStore.run(trimmed, { typed = true, refresh = ConsoleStore.ALL_LISTS })
		end
		-- FocusLost has already run; take focus back on the next frame so typing can continue.
		task.defer(function()
			if boxRef.current and ConsoleStore.get().open then
				boxRef.current:CaptureFocus()
			end
		end)
	end

	React.useEffect(function()
		local connection = UserInputService.InputBegan:Connect(function(input)
			local box = boxRef.current
			if not box or UserInputService:GetFocusedTextBox() ~= box then
				return
			end
			if input.KeyCode == Enum.KeyCode.Tab then
				local first = latest.current.suggestions[1]
				if first then
					replaceLine(first.line)
				end
			elseif input.KeyCode == Enum.KeyCode.Up or input.KeyCode == Enum.KeyCode.Down then
				local history = ConsoleStore.history()
				if #history == 0 then
					return
				end
				local index = historyIndex.current
				if input.KeyCode == Enum.KeyCode.Up then
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
		end)
		return function()
			connection:Disconnect()
		end
	end, {})

	local children: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		}),
		Rule = e("Frame", {
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = theme.color.stroke,
			BackgroundTransparency = 0.6,
			BorderSizePixel = 0,
			LayoutOrder = 0,
		}),
	}

	local last = snapshot.last
	if last then
		children.Result = e("ScrollingFrame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = 1,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(),
			ScrollBarThickness = 5,
			ScrollBarImageColor3 = theme.color.stroke,
			ScrollBarImageTransparency = 0.4,
		}, {
			Cap = e("UISizeConstraint", { MaxSize = Vector2.new(math.huge, RESULT_MAX_HEIGHT) }),
			Layout = e("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }),
			Ran = e(Controls.Label, {
				text = "› " .. last.text,
				mono = true,
				size = Controls.MONO,
				color = theme.color.textMuted,
				layoutOrder = 1,
			}),
			Message = e(Controls.Label, {
				text = (if last.ok then "✓ " else "× ") .. last.message,
				size = Controls.SMALL,
				bold = not last.ok,
				wrap = true,
				color = if last.ok then theme.color.success else theme.color.danger,
				layoutOrder = 2,
			}),
		})
	end

	if analysis.descriptor then
		children.Hint = e(Controls.Label, {
			text = hintText(analysis.descriptor, analysis.argIndex, theme.color.accent)
				.. `  <font color="#{theme.color.textMuted:ToHex()}">{escape(analysis.descriptor.summary)}</font>`,
			richText = true,
			mono = false,
			size = Controls.SMALL,
			wrap = true,
			layoutOrder = 2,
		})
	end

	local rows: { [string]: any } = {
		Layout = e("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }),
	}
	for index, suggestion in ipairs(suggestions) do
		local first = index == 1
		rows[`s{index}`] = e("TextButton", {
			Text = "",
			Size = UDim2.new(1, 0, 0, SUGGESTION_ROW),
			LayoutOrder = index,
			BackgroundColor3 = theme.color.accent,
			BackgroundTransparency = if first then 0.84 else 1,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			[React.Event.Activated] = function()
				replaceLine(suggestion.line)
				if boxRef.current then
					boxRef.current:CaptureFocus()
				end
			end,
		}, {
			Padding = Controls.padding(8),
			Name = e(Controls.Label, {
				text = suggestion.label,
				mono = true,
				size = Controls.MONO,
				height = SUGGESTION_ROW,
				width = UDim.new(if suggestion.detail then 0.45 else 1, 0),
				color = if first then theme.color.accent else theme.color.textPrimary,
			}),
			Detail = if suggestion.detail
				then e("Frame", {
					Size = UDim2.new(0.55, 0, 1, 0),
					Position = UDim2.fromScale(0.45, 0),
					BackgroundTransparency = 1,
				}, {
					Text = e(Controls.Label, {
						text = suggestion.detail,
						size = Controls.SMALL,
						height = SUGGESTION_ROW,
						color = theme.color.textMuted,
					}),
				})
				else nil,
			Tab = if first and not suggestion.detail
				then e("Frame", {
					Size = UDim2.new(0, 44, 1, 0),
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.fromScale(1, 0),
					BackgroundTransparency = 1,
				}, {
					Text = e(Controls.Label, {
						text = "TAB",
						bold = true,
						size = Controls.SMALL,
						height = SUGGESTION_ROW,
						alignX = Enum.TextXAlignment.Right,
						color = theme.color.accent,
					}),
				})
				else nil,
		})
	end

	children.Input = e("Frame", {
		Size = UDim2.new(1, 0, 0, 36),
		LayoutOrder = 4,
		-- Above the result and hint, which the suggestion list opens over.
		ZIndex = 5,
		BackgroundColor3 = theme.color.surface,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
	}, {
		Stroke = e("UIStroke", {
			Color = if focused then theme.color.accent else theme.color.stroke,
			Transparency = if focused then 0 else 0.45,
			Thickness = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		Suggestions = if #suggestions > 0
			then e("Frame", {
				Size = UDim2.new(1, 0, 0, #suggestions * SUGGESTION_ROW + 2),
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.new(0, 0, 0, -4),
				BackgroundColor3 = theme.color.surface,
				BackgroundTransparency = 0.04,
				BorderSizePixel = 0,
				ZIndex = 30,
			}, {
				Stroke = e("UIStroke", {
					Color = theme.color.accent,
					Transparency = 0.45,
					Thickness = 1,
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				}),
				Rows = e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 30 }, rows),
			})
			else nil,
		Prompt = e(Controls.Label, {
			text = "›",
			bold = true,
			size = 22,
			height = 36,
			width = UDim.new(0, 26),
			alignX = Enum.TextXAlignment.Center,
			color = if focused then theme.color.accent else theme.color.textMuted,
		}),
		Box = e("TextBox", {
			ref = boxRef,
			Text = text,
			PlaceholderText = "type a command — help lists them",
			PlaceholderColor3 = theme.color.textMuted,
			Size = UDim2.new(1, -100, 1, 0),
			Position = UDim2.fromOffset(26, 0),
			BackgroundTransparency = 1,
			ClearTextOnFocus = false,
			FontFace = theme.face.mono,
			TextSize = 18,
			TextColor3 = theme.color.textPrimary,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.None,
			ClipsDescendants = true,
			[React.Change.Text] = function(box: TextBox)
				-- Tab and the console's own toggle key reach the box as characters; neither belongs in a
				-- command.
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
		Run = e("Frame", {
			Size = UDim2.new(0, 70, 1, -8),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -4, 0.5, 0),
			BackgroundTransparency = 1,
		}, {
			Button = e(Controls.Button, {
				text = "Run",
				width = 66,
				enabled = text ~= "",
				onActivated = function()
					submit(text)
				end,
			}),
		}),
	})

	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
		ZIndex = 20,
	}, children)
end

return CommandBar
