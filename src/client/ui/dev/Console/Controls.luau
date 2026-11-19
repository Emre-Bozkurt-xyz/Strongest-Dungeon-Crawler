--!strict
-- The console's small controls, in the System look: hairline outlines in white light, cyan only on
-- what has focus (hover, the field being typed in, the picked choice), red for failure.
--
-- The console is a dense developer tool laid out in screen pixels, so these are slimmer than the
-- game's panel components (whose buttons scale display type to their box), but held to the same
-- readability floor: nothing under 17px, bold body face for labels, mono for values and command text,
-- muted ink rather than faint ink for anything that carries information.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ui = script.Parent.Parent.Parent
local ThemeContext = require(ui.hooks.ThemeContext)
local Text = require(ui.components.Text)
local UISound = require(ui.UISound)

local e = React.createElement

local Controls = {}

-- Titillium has a short x-height, so its sizes sit a step above the mono face's.
Controls.TEXT = 19
Controls.SMALL = 18
Controls.MONO = 17
Controls.ROW = 30
Controls.GAP = 6

export type Tone = "default" | "primary" | "danger"

local function padding(x: number, y: number?): any
	return e("UIPadding", {
		PaddingLeft = UDim.new(0, x),
		PaddingRight = UDim.new(0, x),
		PaddingTop = UDim.new(0, y or 0),
		PaddingBottom = UDim.new(0, y or 0),
	})
end
Controls.padding = padding

local function merge(into: { [string]: any }, from: { [string]: any }?)
	for key, value in pairs(from or {}) do
		into[key] = value
	end
	return into
end

-- One line or a wrapped paragraph. Wrapped labels size their height to the text.
function Controls.Label(props: {
	text: string,
	color: Color3?,
	size: number?,
	bold: boolean?,
	mono: boolean?,
	display: boolean?,
	wrap: boolean?,
	width: UDim?,
	height: number?,
	alignX: Enum.TextXAlignment?,
	layoutOrder: number?,
	richText: boolean?,
	fill: boolean?,
	-- As wide as the text, for a label sitting in a row.
	autoWidth: boolean?,
})
	local theme = ThemeContext.useTheme()
	local textSize = props.size or Controls.TEXT
	local face = if props.mono
		then theme.face.mono
		elseif props.display then theme.face.display
		elseif props.bold then theme.face.bodyBold
		else theme.face.body
	local width = if props.autoWidth then UDim.new(0, 0) else props.width or UDim.new(1, 0)
	local auto = props.wrap or props.height == nil
	local automatic = if props.autoWidth
		then (if auto then Enum.AutomaticSize.XY else Enum.AutomaticSize.X)
		elseif auto then Enum.AutomaticSize.Y
		else Enum.AutomaticSize.None
	return e("TextLabel", {
		Text = props.text,
		Size = UDim2.new(width, UDim.new(0, props.height or 0)),
		AutomaticSize = automatic,
		LayoutOrder = props.layoutOrder,
		BackgroundTransparency = 1,
		FontFace = face,
		TextSize = textSize,
		TextColor3 = props.color or theme.color.textPrimary,
		TextXAlignment = props.alignX or Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = props.wrap == true,
		TextTruncate = if props.wrap then Enum.TextTruncate.None else Enum.TextTruncate.AtEnd,
		RichText = props.richText == true,
	}, {
		Flex = if props.fill then e("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }) else nil,
		-- An auto-sized label still keeps a full line's height when its text is empty.
		MinHeight = if auto then e("UISizeConstraint", { MinSize = Vector2.new(0, textSize + 6) }) else nil,
	})
end

-- Children stacked top to bottom; sized to its content.
function Controls.Stack(props: {
	gap: number?,
	pad: number?,
	layoutOrder: number?,
	width: UDim?,
	visible: boolean?,
	children: any?,
})
	local children: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, props.gap or Controls.GAP),
		}),
		Padding = if props.pad then padding(props.pad, props.pad) else nil,
	}
	merge(children, props.children)
	return e("Frame", {
		Size = UDim2.new(props.width or UDim.new(1, 0), UDim.new(0, 0)),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
		Visible = props.visible,
	}, children)
end

-- Children side by side. `wrap` lets a row of buttons flow onto further lines when the dock is
-- narrow.
function Controls.Row(props: {
	gap: number?,
	layoutOrder: number?,
	wrap: boolean?,
	alignY: Enum.VerticalAlignment?,
	alignX: Enum.HorizontalAlignment?,
	height: number?,
	children: any?,
})
	local children: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = props.alignY or Enum.VerticalAlignment.Center,
			HorizontalAlignment = props.alignX or Enum.HorizontalAlignment.Left,
			Padding = UDim.new(0, props.gap or Controls.GAP),
			Wraps = props.wrap == true,
		}),
	}
	merge(children, props.children)
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, props.height or 0),
		AutomaticSize = if props.height then Enum.AutomaticSize.None else Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
	}, children)
end

-- A compact outlined button. `busy` dims it and runs a lit line along its foot while the request it
-- started is out; it ignores clicks meanwhile.
function Controls.Button(props: {
	text: string,
	onActivated: (() -> ())?,
	enabled: boolean?,
	busy: boolean?,
	tone: Tone?,
	width: number?,
	layoutOrder: number?,
	fill: boolean?,
	selected: boolean?,
})
	local theme = ThemeContext.useTheme()
	local hovered, setHovered = React.useState(false)
	local enabled = props.enabled ~= false and not props.busy
	local tone = props.tone or "default"
	local base = if tone == "danger" then theme.color.danger else theme.color.stroke
	local lit = enabled and (hovered or props.selected)

	local strokeColor = if lit then theme.color.accent else base
	local textColor = if not enabled
		then theme.color.textMuted
		elseif tone == "danger" then theme.color.danger
		elseif props.selected then theme.color.accent
		else theme.color.textPrimary
	local fillTransparency = if lit then 0.86 elseif tone == "primary" then 0.9 else 1

	local children: { [string]: any } = {
		Stroke = e("UIStroke", {
			Color = strokeColor,
			Thickness = 1,
			Transparency = if not enabled then 0.75 elseif lit or tone ~= "default" then 0 else 0.5,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		Padding = padding(10),
	}
	if props.busy then
		children.Busy = e("Frame", {
			Size = UDim2.new(1, 20, 0, 2),
			Position = UDim2.new(0, -10, 1, -2),
			BackgroundColor3 = theme.color.accent,
			BorderSizePixel = 0,
		})
	end
	if props.fill then
		children.Flex = e("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill })
	end

	return e("TextButton", {
		Text = string.upper(props.text),
		Size = UDim2.fromOffset(props.width or 0, Controls.ROW),
		AutomaticSize = if props.width or props.fill then Enum.AutomaticSize.None else Enum.AutomaticSize.X,
		LayoutOrder = props.layoutOrder,
		BackgroundColor3 = if lit then theme.color.accent else theme.color.textPrimary,
		BackgroundTransparency = fillTransparency,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Active = enabled,
		FontFace = theme.face.bodyBold,
		TextSize = Controls.SMALL,
		TextColor3 = textColor,
		TextTruncate = Enum.TextTruncate.AtEnd,
		[React.Event.Activated] = function()
			if enabled and props.onActivated then
				UISound.play("confirm")
				props.onActivated()
			end
		end,
		[React.Event.MouseEnter] = function()
			setHovered(true)
		end,
		[React.Event.MouseLeave] = function()
			setHovered(false)
		end,
	}, children)
end

-- A one-line text field. Controlled by `text`; `onChange` sees every edit, `onSubmit` the Enter key.
function Controls.Field(props: {
	text: string,
	placeholder: string?,
	onChange: ((string) -> ())?,
	onSubmit: ((string) -> ())?,
	mono: boolean?,
	width: number?,
	fill: boolean?,
	layoutOrder: number?,
	invalid: boolean?,
	captureFocus: boolean?,
})
	local theme = ThemeContext.useTheme()
	local focused, setFocused = React.useState(false)
	local ref = React.useRef(nil :: TextBox?)

	React.useEffect(function()
		if props.captureFocus and ref.current then
			ref.current:CaptureFocus()
		end
	end, { props.captureFocus })

	local children: { [string]: any } = {
		Stroke = e("UIStroke", {
			Color = if props.invalid then theme.color.danger elseif focused then theme.color.accent else theme.color.stroke,
			Thickness = 1,
			Transparency = if focused or props.invalid then 0 else 0.6,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		Padding = padding(8),
	}
	if props.fill then
		children.Flex = e("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill })
	end

	return e("TextBox", {
		ref = ref,
		Text = props.text,
		PlaceholderText = props.placeholder or "",
		PlaceholderColor3 = theme.color.textMuted,
		-- A filling field starts from no width, so the flex share is all it takes and it never pushes a
		-- button beside it out of the row.
		Size = if props.width
			then UDim2.fromOffset(props.width, Controls.ROW)
			elseif props.fill then UDim2.fromOffset(0, Controls.ROW)
			else UDim2.new(1, 0, 0, Controls.ROW),
		LayoutOrder = props.layoutOrder,
		BackgroundColor3 = theme.color.surface,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		FontFace = if props.mono then theme.face.mono else theme.face.body,
		TextSize = if props.mono then Controls.MONO else Controls.TEXT,
		TextColor3 = theme.color.textPrimary,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		[React.Change.Text] = function(box: TextBox)
			if props.onChange and box.Text ~= props.text then
				props.onChange(box.Text)
			end
		end,
		[React.Event.Focused] = function()
			setFocused(true)
		end,
		[React.Event.FocusLost] = function(box: TextBox, enterPressed: boolean)
			-- The Text change signal is deferred and can land after this; hand the edit over first so
			-- the re-render below never puts the old text back.
			if props.onChange and box.Text ~= props.text then
				props.onChange(box.Text)
			end
			setFocused(false)
			if enterPressed and props.onSubmit then
				props.onSubmit(box.Text)
			end
		end,
	}, children)
end

-- An on/off switch. Lit in the focus colour when on, since an enabled debug flag is something that
-- wants attention.
function Controls.Toggle(props: { value: boolean, onToggle: (() -> ())?, busy: boolean?, layoutOrder: number? })
	local theme = ThemeContext.useTheme()
	local on = props.value
	return e("TextButton", {
		Text = "",
		Size = UDim2.fromOffset(46, 24),
		LayoutOrder = props.layoutOrder,
		BackgroundColor3 = if on then theme.color.accent else theme.color.surface,
		BackgroundTransparency = if on then 0.55 else 0.3,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Active = not props.busy,
		[React.Event.Activated] = function()
			if not props.busy and props.onToggle then
				UISound.play("confirm")
				props.onToggle()
			end
		end,
	}, {
		Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
		Stroke = e("UIStroke", {
			Color = if on then theme.color.accent else theme.color.stroke,
			Transparency = if on then 0 else 0.45,
			Thickness = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		Knob = e("Frame", {
			Size = UDim2.fromOffset(16, 16),
			AnchorPoint = Vector2.new(if on then 1 else 0, 0.5),
			Position = if on then UDim2.new(1, -4, 0.5, 0) else UDim2.new(0, 4, 0.5, 0),
			BackgroundColor3 = if on then theme.color.textPrimary else theme.color.textMuted,
			BackgroundTransparency = if props.busy then 0.5 else 0,
			BorderSizePixel = 0,
		}, {
			Corner = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
		}),
	})
end

-- A small framed tag: "CODE", "STAGE", "CURRENT".
function Controls.Chip(props: { text: string, color: Color3?, filled: boolean?, layoutOrder: number? })
	local theme = ThemeContext.useTheme()
	local color = props.color or theme.color.textMuted
	return e("TextLabel", {
		Text = string.upper(props.text),
		Size = UDim2.fromOffset(0, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = props.layoutOrder,
		BackgroundColor3 = color,
		BackgroundTransparency = if props.filled then 0 else 1,
		BorderSizePixel = 0,
		FontFace = theme.face.bodyBold,
		TextSize = Controls.SMALL,
		TextColor3 = if props.filled then theme.color.textOnAccent else color,
	}, {
		Padding = padding(7),
		Stroke = e("UIStroke", {
			Color = color,
			Thickness = 1,
			Transparency = if props.filled then 1 else 0.2,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
	})
end

-- A titled block: a lit marker, the title in small caps, an optional control on the right, and a
-- hairline fading out under it.
function Controls.Section(props: { title: string, layoutOrder: number?, right: any?, children: any? })
	local theme = ThemeContext.useTheme()
	local body: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, Controls.GAP),
		}),
		Heading = e("Frame", {
			Size = UDim2.new(1, 0, 0, Controls.ROW),
			BackgroundTransparency = 1,
			LayoutOrder = -1000,
		}, {
			Marker = e("Frame", {
				Size = UDim2.fromOffset(7, 7),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0, 5, 0.5, 0),
				Rotation = 45,
				BackgroundColor3 = theme.color.stroke,
				BorderSizePixel = 0,
			}),
			Title = e(Text, {
				text = string.upper(props.title),
				size = UDim2.new(1, -18, 1, 0),
				position = UDim2.fromOffset(18, 0),
				textSize = Controls.SMALL,
				props = { FontFace = theme.face.bodyBold, TextColor3 = theme.color.textPrimary },
			}),
			Right = if props.right
				then e("Frame", {
					Size = UDim2.fromScale(0.7, 1),
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.fromScale(1, 0),
					BackgroundTransparency = 1,
				}, {
					Layout = e("UIListLayout", {
						FillDirection = Enum.FillDirection.Horizontal,
						HorizontalAlignment = Enum.HorizontalAlignment.Right,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, Controls.GAP),
					}),
					Content = props.right,
				})
				else nil,
			Rule = e("Frame", {
				Size = UDim2.new(1, 0, 0, 1),
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				BackgroundColor3 = theme.color.stroke,
				BorderSizePixel = 0,
			}, {
				Fade = e("UIGradient", {
					Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 0.35),
						NumberSequenceKeypoint.new(1, 1),
					}),
				}),
			}),
		}),
	}
	merge(body, props.children)
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
	}, body)
end

-- A row's frame: a faint band of light with a hairline, lit in the focus colour when `current` and in
-- red when `alert`.
function Controls.Card(props: {
	layoutOrder: number?,
	current: boolean?,
	alert: boolean?,
	gap: number?,
	children: any?,
})
	local theme = ThemeContext.useTheme()
	local edge = if props.alert then theme.color.danger elseif props.current then theme.color.accent else theme.color.stroke
	local children: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, props.gap or 4),
		}),
		Padding = padding(10, 8),
		Stroke = e("UIStroke", {
			Color = edge,
			Thickness = 1,
			Transparency = if props.current or props.alert then 0.1 else 0.8,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
	}
	merge(children, props.children)
	-- The marked state is carried by the edge and a tint of its colour: a scale-sized accent bar inside
	-- an auto-sized frame feeds back into the frame's height.
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = props.layoutOrder,
		BackgroundColor3 = if props.current or props.alert then edge else theme.color.textPrimary,
		BackgroundTransparency = if props.current or props.alert then 0.92 else 0.96,
		BorderSizePixel = 0,
	}, children)
end

-- Read-only mono text in a scrolling well, selectable so it can be copied with Ctrl+A, Ctrl+C
-- (Roblox has no clipboard API). As tall as the text up to `height`, then it scrolls.
function Controls.CodeView(props: { text: string, height: number?, layoutOrder: number? })
	local theme = ThemeContext.useTheme()
	local _, lineBreaks = string.gsub(props.text, "\n", "")
	-- Lines of mono text plus the well's padding and room for a horizontal scroll bar.
	local natural = (lineBreaks + 1) * (Controls.MONO + 2) + 16 + 8
	return e("ScrollingFrame", {
		Size = UDim2.new(1, 0, 0, math.min(natural, props.height or 220)),
		LayoutOrder = props.layoutOrder,
		BackgroundColor3 = theme.color.surface,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.XY,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = theme.color.stroke,
		ScrollBarImageTransparency = 0.4,
		ScrollingDirection = Enum.ScrollingDirection.XY,
	}, {
		Stroke = e("UIStroke", {
			Color = theme.color.stroke,
			Transparency = 0.7,
			Thickness = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		Body = e("TextBox", {
			Text = props.text,
			Size = UDim2.fromOffset(0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundTransparency = 1,
			ClearTextOnFocus = false,
			TextEditable = false,
			MultiLine = true,
			TextWrapped = false,
			FontFace = theme.face.mono,
			TextSize = Controls.MONO,
			TextColor3 = theme.color.textPrimary,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
		}, {
			Padding = padding(10, 8),
		}),
	})
end

-- Pick one of a list of strings. Closed it reads like a field showing the value; open it shows a
-- filter and the matching choices inline (inline rather than floating, so it can sit in a scrolling
-- tab without being clipped). Enter in the filter takes the first match.
function Controls.Choice(props: {
	value: string?,
	choices: { string },
	onPick: (string?) -> (),
	placeholder: string?,
	allowClear: boolean?,
	width: number?,
	fill: boolean?,
	layoutOrder: number?,
	maxRows: number?,
})
	local theme = ThemeContext.useTheme()
	local open, setOpen = React.useState(false)
	local filter, setFilter = React.useState("")

	local matches: { string } = {}
	local needle = string.lower(filter)
	for _, choice in ipairs(props.choices) do
		if needle == "" or string.find(string.lower(choice), needle, 1, true) then
			table.insert(matches, choice)
		end
	end

	local function pick(value: string?)
		setOpen(false)
		setFilter("")
		props.onPick(value)
	end

	local head = e("TextButton", {
		Text = "",
		Size = UDim2.new(1, 0, 0, Controls.ROW),
		BackgroundColor3 = theme.color.surface,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		LayoutOrder = 1,
		[React.Event.Activated] = function()
			setOpen(not open)
			setFilter("")
		end,
	}, {
		Stroke = e("UIStroke", {
			Color = if open then theme.color.accent else theme.color.stroke,
			Transparency = if open then 0 else 0.6,
			Thickness = 1,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		Value = e(Text, {
			text = props.value or props.placeholder or "choose…",
			size = UDim2.new(1, -36, 1, 0),
			position = UDim2.fromOffset(8, 0),
			textSize = Controls.MONO,
			props = {
				FontFace = theme.face.mono,
				TextColor3 = if props.value then theme.color.textPrimary else theme.color.textMuted,
				TextTruncate = Enum.TextTruncate.AtEnd,
			},
		}),
		Caret = e(Text, {
			text = if open then "▴" else "▾",
			size = UDim2.new(0, 24, 1, 0),
			position = UDim2.new(1, -28, 0, 0),
			alignX = Enum.TextXAlignment.Center,
			textSize = Controls.TEXT,
			props = { TextColor3 = theme.color.textMuted },
		}),
	})

	local children: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 2),
		}),
		Head = head,
	}

	if open then
		children.Filter = e(Controls.Field, {
			text = filter,
			placeholder = `filter {#props.choices} choices`,
			onChange = setFilter,
			onSubmit = function()
				if matches[1] then
					pick(matches[1])
				end
			end,
			mono = true,
			layoutOrder = 2,
			captureFocus = true,
		})
		local rows: { [string]: any } = {
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		}
		local order = 0
		local function addRow(key: string, label: string, value: string?, muted: boolean?)
			order += 1
			local current = value ~= nil and value == props.value
			rows[key] = e("TextButton", {
				Text = label,
				Size = UDim2.new(1, 0, 0, 28),
				LayoutOrder = order,
				BackgroundColor3 = theme.color.accent,
				BackgroundTransparency = if current then 0.82 else 1,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				FontFace = theme.face.mono,
				TextSize = Controls.MONO,
				TextColor3 = if current then theme.color.accent elseif muted then theme.color.textMuted else theme.color.textPrimary,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				[React.Event.Activated] = function()
					pick(value)
				end,
				[React.Event.MouseEnter] = function(button: TextButton)
					button.BackgroundTransparency = 0.88
				end,
				[React.Event.MouseLeave] = function(button: TextButton)
					button.BackgroundTransparency = if current then 0.82 else 1
				end,
			}, { Padding = padding(8) })
		end
		if props.allowClear then
			addRow("_clear", "(none)", nil, true)
		end
		for index, choice in ipairs(matches) do
			addRow(`c{index}`, choice, choice)
		end
		if #matches == 0 then
			addRow("_empty", if #props.choices == 0 then "(no choices right now)" else "(no match)", props.value, true)
		end
		local visibleRows = math.min(order, props.maxRows or 8)
		children.List = e("ScrollingFrame", {
			Size = UDim2.new(1, 0, 0, visibleRows * 28 + 2),
			LayoutOrder = 3,
			BackgroundColor3 = theme.color.surface,
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(),
			ScrollBarThickness = 6,
			ScrollBarImageColor3 = theme.color.stroke,
			ScrollBarImageTransparency = 0.4,
		}, merge(rows, {
			Stroke = e("UIStroke", {
				Color = theme.color.accent,
				Transparency = 0.5,
				Thickness = 1,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
		}))
	end

	if props.fill then
		children.Flex = e("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill })
	end

	return e("Frame", {
		Size = if props.width
			then UDim2.fromOffset(props.width, 0)
			elseif props.fill then UDim2.fromOffset(0, 0)
			else UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
	}, children)
end

-- A label column of fixed width beside a control, for forms.
function Controls.LabelledRow(props: {
	label: string,
	hint: string?,
	labelWidth: number?,
	layoutOrder: number?,
	children: any?,
})
	local theme = ThemeContext.useTheme()
	local labelWidth = props.labelWidth or 130
	local control: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			Padding = UDim.new(0, Controls.GAP),
		}),
	}
	merge(control, props.children)
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
	}, {
		Label = e("Frame", {
			Size = UDim2.fromOffset(labelWidth, Controls.ROW),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
		}, {
			Layout = e("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }),
			Name = e(Controls.Label, {
				text = props.label,
				bold = true,
				height = Controls.ROW,
				layoutOrder = 1,
			}),
			Hint = if props.hint
				then e(Controls.Label, {
					text = props.hint,
					size = Controls.SMALL,
					color = theme.color.textMuted,
					wrap = true,
					layoutOrder = 2,
				})
				else nil,
		}),
		Control = e("Frame", {
			Size = UDim2.new(1, -(labelWidth + Controls.GAP), 0, 0),
			Position = UDim2.fromOffset(labelWidth + Controls.GAP, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
		}, control),
	})
end

-- A one-line result: green when it worked, red when it failed. Multi-line messages wrap.
function Controls.ResultLine(props: { result: { ok: boolean, message: string }?, layoutOrder: number? })
	local theme = ThemeContext.useTheme()
	local result = props.result
	if not result then
		return nil
	end
	return e(Controls.Label, {
		text = (if result.ok then "✓ " else "× ") .. result.message,
		color = if result.ok then theme.color.success else theme.color.danger,
		size = Controls.SMALL,
		bold = not result.ok,
		wrap = true,
		layoutOrder = props.layoutOrder,
	})
end

-- Quotes a value for a command line when it holds spaces or quotes.
function Controls.quote(value: string): string
	if value == "" or string.find(value, "[%s\"']") then
		local escaped = string.gsub(value, "\\", "\\\\")
		escaped = string.gsub(escaped, '"', '\\"')
		return '"' .. escaped .. '"'
	end
	return value
end

return Controls
