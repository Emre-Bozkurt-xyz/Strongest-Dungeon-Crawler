--!strict
-- The console's primitives. Every console screen is composed from these, and these read every
-- colour, face, size and radius from Console/Theme, so a new screen matches without styling.
--
-- The vocabulary is a command palette's: section labels in dim text instead of boxed cards, one-line
-- selectable rows (state dot, title, chips on the right), a detail pane pinned under the list for the
-- selected row, quiet outlined buttons with at most one filled primary per view, pill chips, and
-- keyboard hints. Editors add accordion sections, steppers, sliders, fields that commit on Enter or
-- Tab, and searches whose matches float over the console. Content spans the column's full width and insets itself by Theme.space.pad, so a
-- selected row's band runs edge to edge.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local UISound = require(script.Parent.Parent.Parent.UISound)
local Theme = require(script.Parent.Theme)
local Glyphs = require(script.Parent.Glyphs)

local e = React.createElement
local color = Theme.color
local font = Theme.font
local size = Theme.size
local space = Theme.space

local Controls = {}

export type Tone = "text" | "secondary" | "dim" | "ok" | "bad" | "warn"

local TONES: { [string]: Color3 } = {
	text = color.text,
	secondary = color.secondary,
	dim = color.dim,
	ok = color.okText,
	bad = color.bad,
	warn = color.warn,
}

function Controls.tone(tone: Tone?): Color3
	return TONES[tone or "text"] or color.text
end

function Controls.padding(x: number, y: number?, top: number?, bottom: number?): any
	return e("UIPadding", {
		PaddingLeft = UDim.new(0, x),
		PaddingRight = UDim.new(0, x),
		PaddingTop = UDim.new(0, top or y or 0),
		PaddingBottom = UDim.new(0, bottom or y or 0),
	})
end

function Controls.corner(radius: UDim?): any
	return e("UICorner", { CornerRadius = radius or Theme.radius.control })
end

function Controls.outline(stroke: Color3, transparency: number?): any
	return e("UIStroke", {
		Color = stroke,
		Thickness = 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

local function merge(into: { [string]: any }, from: { [string]: any }?)
	for key, value in pairs(from or {}) do
		into[key] = value
	end
	return into
end

-- Copies `from`'s children into `into`, for building a child table from parts.
Controls.mergeInto = merge

-- When a text field was last pressed. The console hands the keyboard back to its command line after
-- a click, unless that click pressed a field, which may only take focus on release.
local lastFieldPress = 0

function Controls.fieldPressedRecently(): boolean
	return os.clock() - lastFieldPress < 0.5
end

local function notePress(_: Instance, input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		lastFieldPress = os.clock()
	end
end

local function list(direction: Enum.FillDirection, gap: number?, props: { [string]: any }?): any
	return e(
		"UIListLayout",
		merge({
			FillDirection = direction,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, gap or 0),
			VerticalAlignment = if direction == Enum.FillDirection.Horizontal then Enum.VerticalAlignment.Center else nil,
		}, props)
	)
end
Controls.list = list

local function fillFlex(): any
	return e("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill })
end

-- One line or a wrapped paragraph. Without a height it sizes to the text.
function Controls.Text(props: {
	text: string,
	tone: Tone?,
	color: Color3?,
	size: number?,
	mono: boolean?,
	medium: boolean?,
	wrap: boolean?,
	width: UDim?,
	height: number?,
	fill: boolean?,
	autoWidth: boolean?,
	alignX: Enum.TextXAlignment?,
	richText: boolean?,
	layoutOrder: number?,
	zIndex: number?,
})
	local textSize = props.size or (if props.mono then size.mono else size.body)
	local auto = props.wrap or props.height == nil
	local width = if props.autoWidth or props.fill then UDim.new(0, 0) else props.width or UDim.new(1, 0)
	local automatic = if props.autoWidth
		then (if auto then Enum.AutomaticSize.XY else Enum.AutomaticSize.X)
		elseif auto then Enum.AutomaticSize.Y
		else Enum.AutomaticSize.None
	return e("TextLabel", {
		Text = props.text,
		Size = UDim2.new(width, UDim.new(0, props.height or 0)),
		AutomaticSize = automatic,
		LayoutOrder = props.layoutOrder,
		ZIndex = props.zIndex,
		BackgroundTransparency = 1,
		FontFace = if props.mono then font.mono elseif props.medium then font.medium else font.body,
		TextSize = textSize,
		TextColor3 = props.color or Controls.tone(props.tone),
		TextXAlignment = props.alignX or Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = props.wrap == true,
		TextTruncate = if props.wrap then Enum.TextTruncate.None else Enum.TextTruncate.AtEnd,
		RichText = props.richText == true,
	}, {
		Flex = if props.fill then fillFlex() else nil,
		-- An auto-sized label keeps a full line's height when its text is empty.
		MinHeight = if auto then e("UISizeConstraint", { MinSize = Vector2.new(0, math.ceil(textSize * 1.3)) }) else nil,
	})
end

-- Children top to bottom, full width, sized to content. `pad` insets it like a row.
function Controls.Stack(props: { gap: number?, pad: boolean?, layoutOrder: number?, visible: boolean?, children: any? })
	local children: { [string]: any } = {
		Layout = list(Enum.FillDirection.Vertical, props.gap),
		Padding = if props.pad then Controls.padding(space.pad) else nil,
	}
	merge(children, props.children)
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
		Visible = props.visible,
	}, children)
end

-- A line of controls or chips, inset like a row. `wrap` flows it onto more lines in a narrow dock;
-- `inset = false` drops the inset for a line inside an already inset block (the detail pane).
function Controls.Line(props: {
	gap: number?,
	wrap: boolean?,
	height: number?,
	inset: boolean?,
	vertical: number?,
	alignX: Enum.HorizontalAlignment?,
	layoutOrder: number?,
	children: any?,
})
	local inset = if props.inset == false then 0 else space.pad
	local children: { [string]: any } = {
		Layout = list(Enum.FillDirection.Horizontal, props.gap or space.gap, {
			Wraps = props.wrap == true,
			HorizontalAlignment = props.alignX,
		}),
		Padding = Controls.padding(inset, props.vertical or (if inset > 0 then 4 else 0)),
	}
	merge(children, props.children)
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, props.height or 0),
		AutomaticSize = if props.height then Enum.AutomaticSize.None else Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
	}, children)
end

-- A spacer that takes the rest of a line, pushing what follows to the right.
function Controls.Spacer(props: { layoutOrder: number? })
	return e("Frame", { Size = UDim2.fromOffset(0, 1), BackgroundTransparency = 1, LayoutOrder = props.layoutOrder }, {
		Flex = fillFlex(),
	})
end

function Controls.Divider(props: { layoutOrder: number? })
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = color.divider,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder,
	})
end

-- The dim label over a group of rows: "Scenarios · 4", with optional controls at the right.
function Controls.SectionLabel(props: { text: string, right: any?, layoutOrder: number?, first: boolean? })
	local children: { [string]: any } = {
		Layout = list(Enum.FillDirection.Horizontal, space.gap),
		Padding = Controls.padding(space.pad, nil, if props.first then 8 else space.sectionTop, space.sectionBottom),
		Text = e(Controls.Text, { text = props.text, tone = "dim", size = size.secondary, fill = true, height = 24, layoutOrder = 1 }),
	}
	if props.right then
		children.Right = e("Frame", {
			Size = UDim2.fromOffset(0, 24),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			LayoutOrder = 2,
		}, merge({ Layout = list(Enum.FillDirection.Horizontal, space.gap) }, props.right))
	end
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
	}, children)
end

-- A pill tag. Clickable when given `onActivated` (marker chips teleport, target chips pick).
function Controls.Chip(props: {
	text: string,
	tone: Tone?,
	selected: boolean?,
	mono: boolean?,
	onActivated: (() -> ())?,
	busy: boolean?,
	layoutOrder: number?,
})
	local hovered, setHovered = React.useState(false)
	local clickable = props.onActivated ~= nil
	local lit = props.selected or (clickable and hovered)
	local ink = if props.tone then Controls.tone(props.tone) elseif lit then color.text else color.chipText
	local edge = if props.tone == "ok"
		then color.ok
		elseif props.tone == "bad" then color.bad
		elseif props.tone == "warn" then color.warn
		elseif lit then color.strongOutline
		else color.outline
	local tinted = props.tone == "ok" or props.tone == "bad" or props.tone == "warn"
	return e(if clickable then "TextButton" else "TextLabel", {
		Text = props.text .. (if props.busy then " …" else ""),
		Size = UDim2.fromOffset(0, if clickable then 26 else 22),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = props.layoutOrder,
		BackgroundColor3 = color.hover,
		BackgroundTransparency = if clickable and hovered then 0 else 1,
		BorderSizePixel = 0,
		AutoButtonColor = if clickable then false else nil,
		FontFace = if props.mono then font.mono else font.body,
		TextSize = if clickable then size.secondary else size.small,
		TextColor3 = ink,
		[React.Event.Activated] = if clickable
			then function()
				UISound.play("confirm")
				;(props.onActivated :: () -> ())()
			end
			else nil,
		[React.Event.MouseEnter] = if clickable then function()
			setHovered(true)
		end else nil,
		[React.Event.MouseLeave] = if clickable then function()
			setHovered(false)
		end else nil,
	}, {
		Padding = Controls.padding(if clickable then 10 else 8),
		Corner = Controls.corner(Theme.radius.pill),
		Stroke = Controls.outline(edge, if tinted then 0.45 else 0),
	})
end

-- The keys a hint can name. Return has no character in either console face, so it is drawn.
Controls.ENTER = "enter"

-- A keyboard hint: Controls.ENTER for the return key, else the key's text (Tab, `).
function Controls.Kbd(props: { text: string, color: Color3?, layoutOrder: number?, zIndex: number? })
	local ink = props.color or color.kbdText
	local glyph = props.text == Controls.ENTER
	return e("TextLabel", {
		Text = if glyph then "" else props.text,
		Size = UDim2.fromOffset(if glyph then 24 else 0, 20),
		AutomaticSize = if glyph then Enum.AutomaticSize.None else Enum.AutomaticSize.X,
		LayoutOrder = props.layoutOrder,
		ZIndex = props.zIndex,
		BackgroundTransparency = 1,
		FontFace = font.mono,
		TextSize = size.small,
		TextColor3 = ink,
	}, {
		Padding = if glyph then nil else Controls.padding(6),
		Corner = Controls.corner(Theme.radius.small),
		Stroke = Controls.outline(if props.color then props.color else color.outline, if props.color then 0.6 else 0),
		Glyph = if glyph
			then e(Glyphs.Glyph, {
				name = "enter",
				color = ink,
				size = 14,
				thickness = 1.3,
				position = UDim2.fromScale(0.5, 0.5),
				anchorPoint = Vector2.new(0.5, 0.5),
			})
			else nil,
	})
end

-- A quiet outlined button, or the view's one filled `primary`. `kbd` shows a key inside it (the
-- primary's return key, since Enter on an empty command line runs it).
function Controls.Button(props: {
	text: string,
	onActivated: (() -> ())?,
	primary: boolean?,
	enabled: boolean?,
	busy: boolean?,
	selected: boolean?,
	kbd: boolean?,
	width: number?,
	layoutOrder: number?,
})
	local hovered, setHovered = React.useState(false)
	local enabled = props.enabled ~= false and not props.busy
	local primary = props.primary == true
	local lit = enabled and (hovered or props.selected)

	-- A primary that cannot run yet drops its fill rather than fading it: a half-lit light button over
	-- graphite reads as neither on nor off.
	local filled = primary and enabled
	local fill = if filled then color.text elseif lit then color.hover else color.raised
	local ink = if not enabled
		then color.dim
		elseif filled then color.onPrimary
		elseif props.selected then color.text
		else color.buttonText
	local edge = if filled then color.text elseif lit then color.strongOutline else color.buttonOutline

	local label = props.text .. (if props.busy then " …" else "")
	return e("TextButton", {
		Text = "",
		Size = UDim2.fromOffset(props.width or 0, space.control),
		AutomaticSize = if props.width then Enum.AutomaticSize.None else Enum.AutomaticSize.X,
		LayoutOrder = props.layoutOrder,
		BackgroundColor3 = fill,
		BackgroundTransparency = if filled or lit or primary then 0 else 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Active = enabled,
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
	}, {
		Padding = Controls.padding(11),
		Corner = Controls.corner(),
		Stroke = Controls.outline(edge, if enabled then 0 else 0.4),
		Layout = list(Enum.FillDirection.Horizontal, 8, { HorizontalAlignment = Enum.HorizontalAlignment.Center }),
		Label = e("TextLabel", {
			Text = label,
			Size = UDim2.new(if props.width then 1 else 0, 0, 1, 0),
			AutomaticSize = if props.width then Enum.AutomaticSize.None else Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			FontFace = font.medium,
			TextSize = size.secondary,
			TextColor3 = ink,
			TextTruncate = Enum.TextTruncate.AtEnd,
			LayoutOrder = 1,
		}, {
			Flex = if props.width and props.kbd then e("UIFlexItem", { FlexMode = Enum.UIFlexMode.Shrink }) else nil,
		}),
		Key = if props.kbd and not props.busy
			then e(Glyphs.Glyph, { name = "enter", color = ink, size = 14, thickness = 1.4, layoutOrder = 2 })
			else nil,
	})
end

-- A one-line text field. Controlled by `text`; `onChange` sees every edit, `onSubmit` the Enter key.
function Controls.Input(props: {
	text: string,
	placeholder: string?,
	onChange: ((string) -> ())?,
	onSubmit: ((string) -> ())?,
	mono: boolean?,
	width: number?,
	fill: boolean?,
	invalid: boolean?,
	captureFocus: boolean?,
	layoutOrder: number?,
})
	local focused, setFocused = React.useState(false)
	local ref = React.useRef(nil :: TextBox?)

	React.useEffect(function()
		if props.captureFocus and ref.current then
			ref.current:CaptureFocus()
		end
	end, { props.captureFocus })

	return e("TextBox", {
		ref = ref,
		Text = props.text,
		PlaceholderText = props.placeholder or "",
		PlaceholderColor3 = color.dim,
		-- A filling field starts from no width, so the flex share is all it takes and it never pushes a
		-- button beside it out of the line.
		Size = if props.width
			then UDim2.fromOffset(props.width, space.control)
			elseif props.fill then UDim2.fromOffset(0, space.control)
			else UDim2.new(1, 0, 0, space.control),
		LayoutOrder = props.layoutOrder,
		BackgroundColor3 = color.raised,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		FontFace = if props.mono == false then font.body else font.mono,
		TextSize = if props.mono == false then size.secondary else size.monoSmall,
		TextColor3 = color.text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ClipsDescendants = true,
		[React.Change.Text] = function(box: TextBox)
			if props.onChange and box.Text ~= props.text then
				props.onChange(box.Text)
			end
		end,
		[React.Event.InputBegan] = notePress,
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
	}, {
		Flex = if props.fill then fillFlex() else nil,
		Padding = Controls.padding(8),
		Corner = Controls.corner(),
		Stroke = Controls.outline(if props.invalid then color.bad elseif focused then color.strongOutline else color.outline),
	})
end

-- An on/off switch, green when on.
function Controls.Switch(props: { value: boolean, onToggle: (() -> ())?, busy: boolean?, layoutOrder: number? })
	local on = props.value
	return e("TextButton", {
		Text = "",
		Size = UDim2.fromOffset(32, 18),
		LayoutOrder = props.layoutOrder,
		BackgroundColor3 = if on then color.ok else color.off,
		BackgroundTransparency = if props.busy then 0.4 else 0,
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
		Corner = Controls.corner(Theme.radius.pill),
		Knob = e("Frame", {
			Size = UDim2.fromOffset(14, 14),
			AnchorPoint = Vector2.new(if on then 1 else 0, 0.5),
			Position = if on then UDim2.new(1, -2, 0.5, 0) else UDim2.new(0, 2, 0.5, 0),
			BackgroundColor3 = color.panel,
			BorderSizePixel = 0,
		}, {
			Corner = Controls.corner(Theme.radius.pill),
		}),
	})
end

-- A thin gauge (an NPC's health).
function Controls.Bar(props: { ratio: number, color: Color3?, fill: boolean?, width: number?, layoutOrder: number? })
	return e("Frame", {
		Size = UDim2.fromOffset(props.width or 0, 4),
		BackgroundColor3 = color.track,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder,
	}, {
		Flex = if props.fill ~= false then fillFlex() else nil,
		Corner = Controls.corner(UDim.new(0, 2)),
		Value = e("Frame", {
			Size = UDim2.fromScale(math.clamp(props.ratio, 0, 1), 1),
			BackgroundColor3 = props.color or color.ok,
			BorderSizePixel = 0,
		}, {
			Corner = Controls.corner(UDim.new(0, 2)),
		}),
	})
end

-- Keeps a row in view when it becomes the selection, so walking a long list with Up/Down follows it.
local function useScrollIntoView(ref: { current: GuiObject? }, selected: boolean?)
	React.useEffect(function()
		local object = ref.current
		if not (selected and object) then
			return
		end
		local scroller = object:FindFirstAncestorWhichIsA("ScrollingFrame")
		if not scroller then
			return
		end
		local top = object.AbsolutePosition.Y - scroller.AbsolutePosition.Y
		local bottom = top + object.AbsoluteSize.Y
		local window = scroller.AbsoluteWindowSize.Y
		local canvas = scroller.CanvasPosition
		if top < 0 then
			scroller.CanvasPosition = Vector2.new(canvas.X, math.max(0, canvas.Y + top - 8))
		elseif bottom > window then
			scroller.CanvasPosition = Vector2.new(canvas.X, canvas.Y + bottom - window + 8)
		end
	end, { selected } :: { any })
end

-- One selectable line: a state dot, the title, then whatever sits at the right (chips by default).
-- `body` replaces the free middle of the line (the NPC health bar); `titleWidth` fixes the title's
-- width so such a body lines up from row to row.
function Controls.Row(props: {
	title: string,
	mono: boolean?,
	dot: ("on" | "bad" | "off")?,
	chips: { string }?,
	right: any?,
	body: any?,
	titleWidth: number?,
	titleTone: Tone?,
	selected: boolean?,
	onSelect: (() -> ())?,
	layoutOrder: number?,
})
	local hovered, setHovered = React.useState(false)
	local ref = React.useRef(nil :: GuiObject?)
	useScrollIntoView(ref, props.selected)

	local children: { [string]: any } = {
		Layout = list(Enum.FillDirection.Horizontal, space.gap),
		Padding = Controls.padding(space.pad),
		Dot = e("Frame", {
			Size = UDim2.fromOffset(7, 7),
			BackgroundColor3 = if props.dot == "bad" then color.bad else color.ok,
			BackgroundTransparency = if props.dot == "on" or props.dot == "bad" then 0 else 1,
			BorderSizePixel = 0,
			LayoutOrder = 1,
		}, { Corner = Controls.corner(Theme.radius.pill) }),
		Title = e(Controls.Text, {
			text = props.title,
			mono = props.mono,
			medium = not props.mono,
			size = if props.mono then size.mono else size.body,
			tone = props.titleTone,
			height = space.row,
			fill = props.titleWidth == nil and props.body == nil,
			width = if props.titleWidth then UDim.new(0, props.titleWidth) else nil,
			autoWidth = props.titleWidth == nil and props.body ~= nil,
			layoutOrder = 2,
		}),
	}
	if props.body then
		children.Body = e("Frame", {
			Size = UDim2.fromOffset(0, space.row),
			BackgroundTransparency = 1,
			LayoutOrder = 3,
		}, merge({ Flex = fillFlex(), Layout = list(Enum.FillDirection.Horizontal, space.gap) }, props.body))
	end
	for index, chip in ipairs(props.chips or {}) do
		children[`c{index}`] = e(Controls.Chip, { text = chip, layoutOrder = 10 + index })
	end
	if props.right then
		children.Right = e("Frame", {
			Size = UDim2.fromOffset(0, space.row),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			LayoutOrder = 100,
		}, merge({ Layout = list(Enum.FillDirection.Horizontal, space.gap) }, props.right))
	end

	return e("TextButton", {
		ref = ref,
		Text = "",
		Size = UDim2.new(1, 0, 0, space.row),
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
		Content = e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, children),
		-- A hairline at the selected row's left edge, so the selection still reads where the band
		-- alone is faint.
		Mark = if props.selected
			then e("Frame", {
				Size = UDim2.new(0, 2, 1, 0),
				BackgroundColor3 = color.strongOutline,
				BorderSizePixel = 0,
			})
			else nil,
	})
end

-- A key / value grid for the detail pane.
function Controls.KeyValues(props: { rows: { { any } }, keyWidth: number?, layoutOrder: number? })
	local keyWidth = props.keyWidth or 100
	local children: { [string]: any } = { Layout = list(Enum.FillDirection.Vertical, 2) }
	for index, row in ipairs(props.rows) do
		local key, value, mono = row[1], row[2], row[3]
		children[`r{index}`] = e("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			LayoutOrder = index,
		}, {
			Layout = list(Enum.FillDirection.Horizontal, space.gap, { VerticalAlignment = Enum.VerticalAlignment.Top }),
			Key = e(Controls.Text, {
				text = tostring(key),
				tone = "dim",
				size = size.secondary,
				width = UDim.new(0, keyWidth),
				height = 20,
				layoutOrder = 1,
			}),
			Value = e(Controls.Text, {
				text = tostring(value),
				mono = mono == true,
				size = if mono then size.monoSmall else size.secondary,
				wrap = true,
				width = UDim.new(1, -(keyWidth + space.gap)),
				layoutOrder = 2,
			}),
		})
	end
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
	}, children)
end

-- A label column beside a control, for forms in the detail pane.
function Controls.FormRow(props: { label: string, hint: string?, labelWidth: number?, layoutOrder: number?, children: any? })
	local labelWidth = props.labelWidth or 120
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
	}, {
		Label = e("Frame", {
			Size = UDim2.fromOffset(labelWidth, space.control),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
		}, {
			Layout = list(Enum.FillDirection.Vertical, 0),
			Name = e(Controls.Text, { text = props.label, tone = "secondary", size = size.secondary, height = space.control, layoutOrder = 1 }),
			Hint = if props.hint
				then e(Controls.Text, { text = props.hint, tone = "dim", size = size.small, wrap = true, layoutOrder = 2 })
				else nil,
		}),
		Control = e("Frame", {
			Size = UDim2.new(1, -(labelWidth + space.gap), 0, 0),
			Position = UDim2.fromOffset(labelWidth + space.gap, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
		}, merge({
			Layout = list(Enum.FillDirection.Horizontal, 6, { VerticalAlignment = Enum.VerticalAlignment.Top }),
		}, props.children)),
	})
end

-- The selected row's details and actions, pinned under the list: title and mono id, a description,
-- a key/value grid, anything else the screen needs (`children`), then the actions, primary first.
function Controls.DetailPane(props: {
	title: string,
	id: string?,
	description: string?,
	rows: { { any } }?,
	actions: any?,
	children: any?,
})
	local body: { [string]: any } = {
		Layout = list(Enum.FillDirection.Vertical, 6),
		Head = e("Frame", {
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundTransparency = 1,
			LayoutOrder = 1,
		}, {
			Layout = list(Enum.FillDirection.Horizontal, 10),
			Title = e(Controls.Text, { text = props.title, medium = true, size = 17, height = 24, autoWidth = true, layoutOrder = 1 }),
			Id = if props.id
				then e(Controls.Text, { text = props.id, mono = true, size = size.monoSmall, tone = "dim", height = 24, fill = true, layoutOrder = 2 })
				else nil,
		}),
		Description = if props.description and props.description ~= ""
			then e(Controls.Text, { text = props.description, tone = "secondary", size = size.secondary, wrap = true, layoutOrder = 2 })
			else nil,
		Rows = if props.rows and #props.rows > 0
			then e(Controls.Stack, { layoutOrder = 3 }, {
				Top = e("Frame", { Size = UDim2.fromOffset(1, 2), BackgroundTransparency = 1, LayoutOrder = 0 }),
				Grid = e(Controls.KeyValues, { rows = props.rows, layoutOrder = 1 }),
			})
			else nil,
		Extra = if props.children then e(Controls.Stack, { gap = 6, layoutOrder = 4 }, props.children) else nil,
		Actions = if props.actions
			then e(Controls.Line, { inset = false, wrap = true, vertical = 0, layoutOrder = 5 }, merge({
				Top = e("Frame", { Size = UDim2.new(1, 0, 0, 2), BackgroundTransparency = 1, LayoutOrder = -1 }),
			}, props.actions))
			else nil,
	}
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
	}, {
		Padding = Controls.padding(space.pad, nil, 12, 14),
		Body = e("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
		}, body),
	})
end

-- The tallest the detail pane grows before it scrolls, so a long command form never squeezes the list
-- away entirely.
local DETAIL_MAX_HEIGHT = 420

local function scroller(extra: { [string]: any }): { [string]: any }
	return merge({
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = color.strongOutline,
		ScrollBarImageTransparency = 0.2,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
	}, extra)
end

-- A tab's content column: an optional pinned `top` line, the list (which scrolls), and the detail
-- pane pinned at the foot behind a hairline.
function Controls.TabLayout(props: { top: any?, detail: any?, children: any? })
	local listChildren: { [string]: any } = {
		Layout = list(Enum.FillDirection.Vertical, 0),
		Padding = Controls.padding(0, nil, 0, 12),
	}
	merge(listChildren, props.children)
	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		Layout = list(Enum.FillDirection.Vertical, 0),
		Top = if props.top
			then e("Frame", {
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				LayoutOrder = 1,
			}, { Content = props.top })
			else nil,
		List = e("ScrollingFrame", scroller({
			Size = UDim2.fromScale(1, 0),
			LayoutOrder = 2,
		}), merge({ Flex = fillFlex() }, listChildren)),
		Rule = if props.detail then e(Controls.Divider, { layoutOrder = 3 }) else nil,
		Detail = if props.detail
			then e("ScrollingFrame", scroller({
				Size = UDim2.fromScale(1, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				LayoutOrder = 4,
			}), {
				Cap = e("UISizeConstraint", { MaxSize = Vector2.new(math.huge, DETAIL_MAX_HEIGHT) }),
				Content = props.detail,
			})
			else nil,
	})
end

-- A dim one-line message where a list is empty or still loading; red when it is an error.
function Controls.Empty(props: { text: string, bad: boolean?, layoutOrder: number? })
	return e(Controls.Stack, { pad = true, layoutOrder = props.layoutOrder }, {
		Text = e(Controls.Text, {
			text = props.text,
			tone = if props.bad then "bad" else "dim",
			size = size.secondary,
			wrap = true,
		}),
	})
end

-- A result line: green when it worked, red when it failed.
function Controls.Result(props: { result: { ok: boolean, message: string }?, layoutOrder: number? })
	local result = props.result
	if not result then
		return nil
	end
	return e(Controls.Text, {
		text = (if result.ok then "✓  " else "×  ") .. result.message,
		tone = if result.ok then "ok" else "bad",
		size = size.secondary,
		wrap = true,
		layoutOrder = props.layoutOrder,
	})
end

-- Read-only mono text in a scrolling well, selectable so it can be copied with Ctrl+A, Ctrl+C
-- (Roblox has no clipboard API). As tall as the text up to `height`, then it scrolls.
function Controls.CodeView(props: { text: string, height: number?, layoutOrder: number? })
	local _, lineBreaks = string.gsub(props.text, "\n", "")
	local natural = (lineBreaks + 1) * (size.monoSmall + 4) + 20 + 8
	return e("ScrollingFrame", scroller({
		Size = UDim2.new(1, 0, 0, math.min(natural, props.height or 220)),
		LayoutOrder = props.layoutOrder,
		BackgroundColor3 = color.raised,
		BackgroundTransparency = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.XY,
		ScrollingDirection = Enum.ScrollingDirection.XY,
	}), {
		Corner = Controls.corner(),
		Body = e("TextBox", {
			Text = props.text,
			Size = UDim2.fromOffset(0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundTransparency = 1,
			ClearTextOnFocus = false,
			TextEditable = false,
			MultiLine = true,
			TextWrapped = false,
			FontFace = font.mono,
			TextSize = size.monoSmall,
			TextColor3 = color.text,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			[React.Event.InputBegan] = notePress,
		}, {
			Padding = Controls.padding(10, 10),
		}),
	})
end

-- The layer that floating popups (a select's choices) are drawn into: a frame over the whole dock,
-- above everything in it, so a popup is never clipped by the scrolling list or detail pane it was
-- opened from. The console root registers it.
local overlay: GuiObject? = nil

function Controls.setOverlay(instance: GuiObject?)
	overlay = instance
end

local CHOICE_ROW = 26

-- Pick one of a list of strings. Closed it reads like an input showing the value; open it floats a
-- filter and the matching choices over the console, below the field or above it when there is more
-- room there. Enter in the filter takes the first match; a click anywhere else closes it.
--
-- `labels` shows a choice under another text than its value; `disabled` lists choices that stay
-- visible but cannot be picked, with why beside them (a locked form). `clearLabel` names the empty
-- choice; `compact` drops the caret for a narrow field in a row of several; `invalid` outlines it red.
function Controls.Select(props: {
	value: string?,
	choices: { string },
	onPick: (string?) -> (),
	placeholder: string?,
	allowClear: boolean?,
	clearLabel: string?,
	labels: { [string]: string }?,
	disabled: { [string]: string }?,
	compact: boolean?,
	invalid: boolean?,
	enabled: boolean?,
	width: number?,
	fill: boolean?,
	layoutOrder: number?,
	maxRows: number?,
})
	local labels = props.labels or {}
	local disabled = props.disabled or {}
	-- Where the popup sits in the overlay; `above` anchors it by its foot, so filtering shrinks it
	-- toward the field rather than away from it.
	local placement, setPlacement = React.useState(nil :: { x: number, y: number, width: number, above: boolean }?)
	local filter, setFilter = React.useState("")
	local headRef = React.useRef(nil :: GuiObject?)
	local open = placement ~= nil and overlay ~= nil

	local matches: { string } = {}
	local needle = string.lower(filter)
	for _, choice in ipairs(props.choices) do
		local text = string.lower(choice .. " " .. (labels[choice] or ""))
		if needle == "" or string.find(text, needle, 1, true) then
			table.insert(matches, choice)
		end
	end

	local function close()
		setPlacement(nil)
		setFilter("")
	end

	local function pick(value: string?)
		close()
		props.onPick(value)
	end

	local rowCount = #matches + (if props.allowClear then 1 else 0)
	if #matches == 0 then
		rowCount += 1
	end
	local visibleRows = math.min(rowCount, props.maxRows or 7)
	local popupHeight = space.control + 6 + visibleRows * CHOICE_ROW + 12

	local function openPopup()
		local head = headRef.current
		local layer = overlay
		if not (head and layer) then
			return
		end
		local origin = layer.AbsolutePosition
		local top = head.AbsolutePosition.Y - origin.Y
		local bottom = top + head.AbsoluteSize.Y
		local fullHeight = space.control + 6 + math.min(#props.choices + 1, props.maxRows or 7) * CHOICE_ROW + 12
		local below = layer.AbsoluteSize.Y - bottom
		local above = not (below >= fullHeight + 8 or below >= top)
		local y = if above then top - 4 else bottom + 4
		-- Room for the reason beside a disabled choice.
		local width = math.min(math.max(head.AbsoluteSize.X, if next(disabled) then 300 else 180), layer.AbsoluteSize.X - 16)
		local x = math.clamp(head.AbsolutePosition.X - origin.X, 8, math.max(8, layer.AbsoluteSize.X - width - 8))
		setFilter("")
		setPlacement({ x = x, y = y, width = width, above = above })
	end

	local popup: any = nil
	if open and placement and overlay then
		local rows: { [string]: any } = { Layout = list(Enum.FillDirection.Vertical, 0) }
		local order = 0
		local function addRow(key: string, label: string, value: string?, muted: boolean?, reason: string?)
			order += 1
			local current = value ~= nil and value == props.value
			local pickable = reason == nil and (not muted or props.allowClear == true)
			rows[key] = e("TextButton", {
				Text = "",
				Size = UDim2.new(1, 0, 0, CHOICE_ROW),
				LayoutOrder = order,
				BackgroundColor3 = color.hover,
				BackgroundTransparency = if current then 0 else 1,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				[React.Event.Activated] = function()
					if pickable then
						pick(value)
					end
				end,
				[React.Event.MouseEnter] = function(button: TextButton)
					if pickable then
						button.BackgroundTransparency = 0
					end
				end,
				[React.Event.MouseLeave] = function(button: TextButton)
					button.BackgroundTransparency = if current then 0 else 1
				end,
			}, {
				Padding = Controls.padding(8),
				Corner = Controls.corner(Theme.radius.small),
				Layout = list(Enum.FillDirection.Horizontal, 8),
				Label = e(Controls.Text, {
					text = label,
					mono = true,
					size = size.monoSmall,
					color = if muted or reason then color.dim else color.text,
					height = CHOICE_ROW,
					fill = reason == nil,
					autoWidth = reason ~= nil,
					layoutOrder = 1,
				}),
				Reason = if reason
					then e(Controls.Text, {
						text = reason,
						tone = "dim",
						size = size.small,
						height = CHOICE_ROW,
						fill = true,
						alignX = Enum.TextXAlignment.Right,
						layoutOrder = 2,
					})
					else nil,
			})
		end
		if props.allowClear then
			addRow("_clear", props.clearLabel or "(none)", nil, true)
		end
		for index, choice in ipairs(matches) do
			addRow(`c{index}`, labels[choice] or choice, choice, false, disabled[choice])
		end
		if #matches == 0 then
			addRow("_empty", if #props.choices == 0 then "(no choices right now)" else "(no match)", props.value, true)
		end

		popup = ReactRoblox.createPortal({
			SelectPopup = e("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
			}, {
				-- Catches the click that closes it, and keeps that click from reaching what is underneath.
				Backdrop = e("TextButton", {
					Text = "",
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					AutoButtonColor = false,
					[React.Event.Activated] = close,
				}),
				Panel = e("Frame", {
					Size = UDim2.fromOffset(placement.width, popupHeight),
					Position = UDim2.fromOffset(placement.x, placement.y),
					AnchorPoint = Vector2.new(0, if placement.above then 1 else 0),
					BackgroundColor3 = color.panel,
					BorderSizePixel = 0,
					ZIndex = 2,
				}, {
					Corner = Controls.corner(Theme.radius.large),
					Stroke = Controls.outline(color.strongOutline),
					Padding = Controls.padding(6, 6),
					Layout = list(Enum.FillDirection.Vertical, 6),
					Filter = e(Controls.Input, {
						text = filter,
						placeholder = `filter {#props.choices}`,
						onChange = setFilter,
						onSubmit = function()
							for _, match in ipairs(matches) do
								if not disabled[match] then
									pick(match)
									return
								end
							end
						end,
						layoutOrder = 1,
						captureFocus = true,
					}),
					List = e("ScrollingFrame", scroller({
						Size = UDim2.new(1, 0, 0, visibleRows * CHOICE_ROW),
						LayoutOrder = 2,
					}), rows),
				}),
			}),
		}, overlay)
	end

	return e("Frame", {
		Size = if props.width
			then UDim2.fromOffset(props.width, space.control)
			elseif props.fill then UDim2.fromOffset(0, space.control)
			else UDim2.new(1, 0, 0, space.control),
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
	}, {
		Flex = if props.fill then fillFlex() else nil,
		Head = e("TextButton", {
			ref = headRef,
			Text = "",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = color.raised,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Active = props.enabled ~= false,
			[React.Event.Activated] = function()
				if props.enabled == false then
					return
				end
				if open then
					close()
				else
					openPopup()
				end
			end,
		}, {
			Corner = Controls.corner(),
			Stroke = Controls.outline(
				if props.invalid then color.bad elseif open then color.strongOutline else color.outline
			),
			Padding = Controls.padding(if props.compact then 6 else 8),
			Layout = list(Enum.FillDirection.Horizontal, 4, { HorizontalFlex = Enum.UIFlexAlignment.SpaceBetween }),
			Value = e(Controls.Text, {
				text = if props.value then labels[props.value] or props.value else props.placeholder or "choose",
				mono = props.value ~= nil,
				size = if props.value then size.monoSmall else size.secondary,
				tone = if props.value and props.enabled ~= false then "text" else "dim",
				height = space.control,
				fill = true,
				layoutOrder = 1,
			}),
			Caret = if props.compact
				then nil
				else e(Glyphs.Glyph, {
					name = if open then "caretUp" else "caretDown",
					color = color.dim,
					size = 14,
					layoutOrder = 2,
				}),
		}),
		Popup = popup,
	})
end

-- A small square button showing one glyph (remove, edit, raise to max, attune).
function Controls.IconButton(props: {
	glyph: string,
	onActivated: (() -> ())?,
	color: Color3?,
	size: number?,
	enabled: boolean?,
	layoutOrder: number?,
	zIndex: number?,
})
	local hovered, setHovered = React.useState(false)
	local enabled = props.enabled ~= false and props.onActivated ~= nil
	local box = props.size or 24
	local ink = if not enabled then color.off elseif props.color then props.color elseif hovered then color.text else color.dim
	return e("TextButton", {
		Text = "",
		Size = UDim2.fromOffset(box, box),
		LayoutOrder = props.layoutOrder,
		ZIndex = props.zIndex,
		BackgroundColor3 = color.hover,
		BackgroundTransparency = if enabled and hovered then 0 else 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Active = enabled,
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
	}, {
		Corner = Controls.corner(Theme.radius.small),
		Glyph = e(Glyphs.Glyph, {
			name = props.glyph,
			color = ink,
			size = math.floor(box * 0.62),
			thickness = 1.5,
			position = UDim2.fromScale(0.5, 0.5),
			anchorPoint = Vector2.new(0.5, 0.5),
		}),
	})
end

-- Fields of a form that Tab walks carry this attribute, inside an ancestor marked FIELD_SCOPE; Tab
-- and Shift+Tab move between them in reading order.
local FIELD_TAG = "ConsoleField"
Controls.FIELD_SCOPE = "ConsoleFieldScope"

local function scrollIntoView(object: GuiObject)
	local scroller = object:FindFirstAncestorWhichIsA("ScrollingFrame")
	if not scroller then
		return
	end
	local top = object.AbsolutePosition.Y - scroller.AbsolutePosition.Y
	local bottom = top + object.AbsoluteSize.Y
	local window = scroller.AbsoluteWindowSize.Y
	local canvas = scroller.CanvasPosition
	if top < 0 then
		scroller.CanvasPosition = Vector2.new(canvas.X, math.max(0, canvas.Y + top - 8))
	elseif bottom > window then
		scroller.CanvasPosition = Vector2.new(canvas.X, canvas.Y + bottom - window + 8)
	end
end

local function isShown(object: GuiObject): boolean
	local node: Instance? = object
	while node and node:IsA("GuiObject") do
		if not (node :: GuiObject).Visible then
			return false
		end
		node = node.Parent
	end
	return object.AbsoluteSize.X > 0 and object.AbsoluteSize.Y > 0
end

local function focusNextField(box: TextBox, backwards: boolean)
	local scope: Instance? = box.Parent
	while scope and scope:GetAttribute(Controls.FIELD_SCOPE) ~= true do
		scope = scope.Parent
	end
	if not scope then
		return
	end
	local fields: { TextBox } = {}
	for _, descendant in ipairs(scope:GetDescendants()) do
		if descendant:IsA("TextBox") and descendant:GetAttribute(FIELD_TAG) == true and isShown(descendant) then
			table.insert(fields, descendant)
		end
	end
	table.sort(fields, function(a, b)
		local ay, by = a.AbsolutePosition.Y, b.AbsolutePosition.Y
		if math.abs(ay - by) > 6 then
			return ay < by
		end
		return a.AbsolutePosition.X < b.AbsolutePosition.X
	end)
	local index = table.find(fields, box)
	if not index or #fields < 2 then
		return
	end
	local target = fields[(index - 1 + (if backwards then -1 else 1)) % #fields + 1]
	task.defer(function()
		if target.Parent then
			target:CaptureFocus()
		end
	end)
end

-- One listener for every field: Tab in a focused field commits it (by releasing focus) and moves on.
local tabListener: RBXScriptConnection? = nil
local function listenForTab()
	if tabListener then
		return
	end
	tabListener = UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode ~= Enum.KeyCode.Tab then
			return
		end
		local box = UserInputService:GetFocusedTextBox()
		if box and box:GetAttribute(FIELD_TAG) == true then
			local backwards = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
			box:ReleaseFocus(false)
			focusNextField(box, backwards)
		end
	end)
end

-- A text field that commits: it shows `value`, keeps what is typed as a draft while it has the
-- keyboard, and hands the draft to `onCommit` once, on Enter, Tab or clicking away. A parent that
-- refuses the value simply keeps passing the old one, and the field shows it again.
function Controls.Field(props: {
	value: string,
	onCommit: (string) -> (),
	placeholder: string?,
	width: number?,
	fill: boolean?,
	mono: boolean?,
	invalid: boolean?,
	enabled: boolean?,
	bare: boolean?,
	alignX: Enum.TextXAlignment?,
	layoutOrder: number?,
	children: any?,
})
	local focused, setFocused = React.useState(false)
	local draft, setDraft = React.useState(props.value)
	React.useEffect(listenForTab, {})

	local children: { [string]: any } = {
		Flex = if props.fill then fillFlex() else nil,
		Padding = Controls.padding(if props.bare then 2 else 8),
		Corner = if props.bare then nil else Controls.corner(),
		Stroke = if props.bare
			then nil
			else Controls.outline(if props.invalid then color.bad elseif focused then color.strongOutline else color.outline),
	}
	merge(children, props.children)
	return e("TextBox", {
		Text = if focused then draft else props.value,
		PlaceholderText = props.placeholder or "",
		PlaceholderColor3 = color.dim,
		Size = if props.width
			then UDim2.fromOffset(props.width, space.control)
			elseif props.fill then UDim2.fromOffset(0, space.control)
			else UDim2.new(1, 0, 0, space.control),
		LayoutOrder = props.layoutOrder,
		BackgroundColor3 = color.raised,
		BackgroundTransparency = if props.bare then 1 else 0,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		TextEditable = props.enabled ~= false,
		Active = props.enabled ~= false,
		FontFace = if props.mono == false then font.body else font.mono,
		TextSize = if props.mono == false then size.secondary else size.monoSmall,
		TextColor3 = if props.enabled == false then color.dim elseif props.invalid and not focused then color.bad else color.text,
		TextXAlignment = props.alignX or Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ClipsDescendants = true,
		ref = function(box: TextBox?)
			if box then
				box:SetAttribute(FIELD_TAG, true)
			end
		end,
		[React.Change.Text] = function(box: TextBox)
			if box:IsFocused() then
				local cleaned = string.gsub(string.gsub(box.Text, "\t", ""), "`", "")
				if cleaned ~= box.Text then
					box.Text = cleaned
					return
				end
				setDraft(cleaned)
			end
		end,
		[React.Event.InputBegan] = notePress,
		[React.Event.Focused] = function(box: TextBox)
			setDraft(props.value)
			setFocused(true)
			box.CursorPosition = #box.Text + 1
			scrollIntoView(box)
		end,
		[React.Event.FocusLost] = function(box: TextBox)
			local text = string.gsub(string.gsub(box.Text, "\t", ""), "`", "")
			setFocused(false)
			if text ~= props.value then
				props.onCommit(text)
			end
		end,
	}, children)
end

-- A number with − and + beside it, and the number itself typed exactly. Clamped to min / max.
function Controls.Stepper(props: {
	value: number,
	onChange: (number) -> (),
	min: number?,
	max: number?,
	step: number?,
	width: number?,
	invalid: boolean?,
	enabled: boolean?,
	format: ((number) -> string)?,
	layoutOrder: number?,
})
	local step = props.step or 1
	local enabled = props.enabled ~= false
	local function clamp(value: number): number
		return math.clamp(value, props.min or -math.huge, props.max or math.huge)
	end
	local function change(value: number)
		local nextValue = clamp(value)
		if nextValue ~= props.value then
			props.onChange(nextValue)
		end
	end
	local fieldWidth = props.width or 52
	return e("Frame", {
		Size = UDim2.fromOffset(fieldWidth + 48 + 4, space.control),
		BackgroundColor3 = color.raised,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder,
	}, {
		Corner = Controls.corner(),
		Stroke = Controls.outline(if props.invalid then color.bad else color.outline),
		Padding = Controls.padding(2),
		Layout = list(Enum.FillDirection.Horizontal, 0),
		Minus = e(Controls.IconButton, {
			glyph = "minus",
			enabled = enabled and props.value > (props.min or -math.huge),
			layoutOrder = 1,
			onActivated = function()
				change(props.value - step)
			end,
		}),
		Value = e(Controls.Field, {
			value = if props.format then props.format(props.value) else tostring(props.value),
			bare = true,
			width = fieldWidth,
			alignX = Enum.TextXAlignment.Center,
			invalid = props.invalid,
			enabled = enabled,
			layoutOrder = 2,
			onCommit = function(text)
				local number = tonumber(text)
				if number then
					change(number)
				end
			end,
		}),
		Plus = e(Controls.IconButton, {
			glyph = "plus",
			enabled = enabled and props.value < (props.max or math.huge),
			layoutOrder = 3,
			onActivated = function()
				change(props.value + step)
			end,
		}),
	})
end

-- A draggable gauge. `onChange(ratio, done)` follows the drag (done = false) and the release (done
-- = true), so a parent can show the value live and send it once.
function Controls.Slider(props: {
	ratio: number,
	onChange: (number, boolean) -> (),
	enabled: boolean?,
	width: number?,
	fill: boolean?,
	layoutOrder: number?,
})
	local dragging, setDragging = React.useState(nil :: number?)
	local trackRef = React.useRef(nil :: GuiObject?)
	local connections = React.useRef({} :: { RBXScriptConnection })
	local enabled = props.enabled ~= false

	local function stop()
		for _, connection in ipairs(connections.current) do
			connection:Disconnect()
		end
		connections.current = {}
	end
	React.useEffect(function()
		return stop
	end, {})

	local function ratioAt(x: number): number
		local track = trackRef.current
		if not track or track.AbsoluteSize.X <= 0 then
			return props.ratio
		end
		return math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
	end

	local function begin(input: InputObject)
		if not enabled or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		stop()
		local ratio = ratioAt(input.Position.X)
		setDragging(ratio)
		props.onChange(ratio, false)
		table.insert(connections.current, UserInputService.InputChanged:Connect(function(moved)
			if moved.UserInputType == Enum.UserInputType.MouseMovement then
				local next = ratioAt(moved.Position.X)
				setDragging(next)
				props.onChange(next, false)
			end
		end))
		table.insert(connections.current, UserInputService.InputEnded:Connect(function(ended)
			if ended.UserInputType == Enum.UserInputType.MouseButton1 then
				local final = ratioAt(ended.Position.X)
				stop()
				setDragging(nil)
				props.onChange(final, true)
			end
		end))
	end

	local ratio = math.clamp(dragging or props.ratio, 0, 1)
	local ink = if enabled then color.text else color.off
	return e("TextButton", {
		Text = "",
		Size = UDim2.fromOffset(props.width or 0, 20),
		LayoutOrder = props.layoutOrder,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Active = enabled,
		[React.Event.InputBegan] = function(_, input: InputObject)
			begin(input)
		end,
	}, {
		Flex = if props.fill ~= false and not props.width then fillFlex() else nil,
		-- Inset by the knob's radius, so the knob stays inside the control at either end.
		Track = e("Frame", {
			ref = trackRef,
			Size = UDim2.new(1, -12, 0, 4),
			Position = UDim2.new(0, 6, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = color.track,
			BorderSizePixel = 0,
		}, {
			Corner = Controls.corner(UDim.new(0, 2)),
			Value = e("Frame", {
				Size = UDim2.fromScale(ratio, 1),
				BackgroundColor3 = ink,
				BorderSizePixel = 0,
			}, { Corner = Controls.corner(UDim.new(0, 2)) }),
			Knob = e("Frame", {
				Size = UDim2.fromOffset(12, 12),
				Position = UDim2.fromScale(ratio, 0.5),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = ink,
				BorderSizePixel = 0,
			}, { Corner = Controls.corner(Theme.radius.pill) }),
		}),
	})
end

-- Roblox can leave controls that mount into an already laid-out list out of what a click hits (no
-- hover, no click) until something in that part of the tree changes order. Bumping the container's
-- ZIndex for a frame and putting it back makes the engine rebuild that, with nothing to see.
function Controls.useHitRefresh(ref: { current: GuiObject? }, deps: { any })
	React.useEffect(function()
		local cancelled = false
		task.defer(function()
			task.wait()
			local object = ref.current
			if cancelled or not object then
				return
			end
			local z = object.ZIndex
			object.ZIndex = z + 1
			task.wait()
			if object.Parent then
				object.ZIndex = z
			end
		end)
		return function()
			cancelled = true
		end
	end, deps)
end

-- How far an accordion section's body is inset: under its title, past the caret.
Controls.SECTION_INSET = space.pad + 14 + space.gap

-- One accordion section: a header line (caret, title, and a one-line summary at the right that says
-- what is inside while it is closed) over its body when open.
function Controls.Section(props: {
	title: string,
	summary: string?,
	summaryTone: Tone?,
	open: boolean,
	onToggle: () -> (),
	layoutOrder: number?,
	children: any?,
})
	local hovered, setHovered = React.useState(false)
	local bodyRef = React.useRef(nil :: GuiObject?)
	Controls.useHitRefresh(bodyRef, { props.open })
	local body: { [string]: any } = {
		Layout = list(Enum.FillDirection.Vertical, 2),
		Padding = Controls.padding(0, nil, 0, 10),
	}
	merge(body, props.children)
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
	}, {
		Layout = list(Enum.FillDirection.Vertical, 0),
		Rule = e(Controls.Divider, { layoutOrder = 1 }),
		Header = e("TextButton", {
			Text = "",
			Size = UDim2.new(1, 0, 0, 38),
			LayoutOrder = 2,
			BackgroundColor3 = color.hover,
			BackgroundTransparency = if hovered then 0.55 else 1,
			BorderSizePixel = 0,
			AutoButtonColor = false,
			[React.Event.Activated] = function()
				UISound.play("confirm")
				props.onToggle()
			end,
			[React.Event.MouseEnter] = function()
				setHovered(true)
			end,
			[React.Event.MouseLeave] = function()
				setHovered(false)
			end,
		}, {
			Padding = Controls.padding(space.pad),
			Layout = list(Enum.FillDirection.Horizontal, space.gap),
			Caret = e(Glyphs.Glyph, {
				name = if props.open then "caretDown" else "caretRight",
				color = color.dim,
				size = 14,
				layoutOrder = 1,
			}),
			Title = e(Controls.Text, { text = props.title, medium = true, height = 38, autoWidth = true, layoutOrder = 2 }),
			Summary = e(Controls.Text, {
				text = props.summary or "",
				tone = props.summaryTone or "secondary",
				size = size.secondary,
				height = 38,
				fill = true,
				alignX = Enum.TextXAlignment.Right,
				layoutOrder = 3,
			}),
		}),
		Body = if props.open
			then e("Frame", {
				ref = bodyRef,
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
				LayoutOrder = 3,
			}, body)
			else nil,
	})
end

export type SearchItem = {
	key: string,
	label: string,
	-- Dim text after the label ("infusion", "passive").
	kind: string?,
	-- Mono text at the right ("Fire trunk → 400").
	detail: string?,
	-- Why it cannot be picked; shown in place of the detail.
	disabled: string?,
}

local SEARCH_ROW = 30
local SEARCH_LIMIT = 60

-- A search field whose matches float in a list over the console (the overlay layer, so nothing
-- clips it): the node search, add a skill, an item, a stat. Every typed word must appear in an
-- item's label, key or kind. Up/Down move the highlight, Enter takes it, a click takes any row.
function Controls.Search(props: {
	items: { SearchItem },
	onPick: (string) -> (),
	placeholder: string?,
	hint: string?,
	width: number?,
	fill: boolean?,
	maxRows: number?,
	layoutOrder: number?,
})
	local text, setText = React.useState("")
	local open, setOpen = React.useState(false)
	local highlight, setHighlight = React.useState(1)
	local placement, setPlacement = React.useState(nil :: { x: number, y: number, width: number, above: boolean }?)
	local boxRef = React.useRef(nil :: TextBox?)
	local closeToken = React.useRef(0)
	React.useEffect(listenForTab, {})

	local words: { string } = {}
	for word in string.gmatch(string.lower(text), "%S+") do
		table.insert(words, word)
	end
	local matches: { SearchItem } = {}
	for _, item in ipairs(props.items) do
		local haystack = string.lower(`{item.label} {item.key} {item.kind or ""}`)
		local all = true
		for _, word in ipairs(words) do
			if not string.find(haystack, word, 1, true) then
				all = false
				break
			end
		end
		if all then
			table.insert(matches, item)
			if #matches >= SEARCH_LIMIT then
				break
			end
		end
	end
	local selected = math.clamp(highlight, 1, math.max(1, #matches))

	-- The latest matches and highlight, for the key listener below.
	local latest = React.useRef({ matches = matches, selected = selected })
	latest.current = { matches = matches, selected = selected }

	local function close()
		closeToken.current += 1
		setOpen(false)
	end

	local function pick(item: SearchItem?)
		if not item or item.disabled then
			return
		end
		setText("")
		setHighlight(1)
		close()
		if boxRef.current then
			boxRef.current:ReleaseFocus(false)
		end
		props.onPick(item.key)
	end

	local function place()
		-- The field's outline, not the text box inset inside it past the glyph.
		local parent = boxRef.current and boxRef.current.Parent
		local layer = overlay
		if not (parent and layer and parent:IsA("GuiObject")) then
			return
		end
		local box = parent :: GuiObject
		local origin = layer.AbsolutePosition
		local top = box.AbsolutePosition.Y - origin.Y
		local bottom = top + box.AbsoluteSize.Y
		local wanted = math.min(#props.items + 1, props.maxRows or 8) * SEARCH_ROW + 12
		local below = layer.AbsoluteSize.Y - bottom
		local above = not (below >= wanted + 8 or below >= top)
		local width = math.min(math.max(box.AbsoluteSize.X, 260), layer.AbsoluteSize.X - 16)
		local x = math.clamp(box.AbsolutePosition.X - origin.X, 8, math.max(8, layer.AbsoluteSize.X - width - 8))
		setPlacement({ x = x, y = if above then top - 4 else bottom + 4, width = width, above = above })
	end

	React.useEffect(function()
		if not open then
			return
		end
		local connection = UserInputService.InputBegan:Connect(function(input)
			if UserInputService:GetFocusedTextBox() ~= boxRef.current then
				return
			end
			local current = latest.current
			if input.KeyCode == Enum.KeyCode.Down then
				setHighlight(math.min(current.selected + 1, math.max(1, #current.matches)))
			elseif input.KeyCode == Enum.KeyCode.Up then
				setHighlight(math.max(current.selected - 1, 1))
			end
		end)
		return function()
			connection:Disconnect()
		end
	end, { open })

	local popup: any = nil
	if open and placement and overlay then
		local rows: { [string]: any } = { Layout = list(Enum.FillDirection.Vertical, 0) }
		for index, item in ipairs(matches) do
			local lit = index == selected and not item.disabled
			rows[`r{index}`] = e("TextButton", {
				Text = "",
				Size = UDim2.new(1, 0, 0, SEARCH_ROW),
				LayoutOrder = index,
				BackgroundColor3 = color.hover,
				BackgroundTransparency = if lit then 0 else 1,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				[React.Event.Activated] = function()
					pick(item)
				end,
				[React.Event.MouseEnter] = function()
					setHighlight(index)
				end,
			}, {
				Padding = Controls.padding(8),
				Corner = Controls.corner(Theme.radius.small),
				Layout = list(Enum.FillDirection.Horizontal, 6),
				Label = e(Controls.Text, {
					text = item.label,
					color = if item.disabled then color.dim else color.text,
					size = size.secondary,
					height = SEARCH_ROW,
					autoWidth = true,
					layoutOrder = 1,
				}),
				Kind = if item.kind
					then e(Controls.Text, { text = item.kind, tone = "dim", size = size.small, height = SEARCH_ROW, autoWidth = true, layoutOrder = 2 })
					else nil,
				Detail = e(Controls.Text, {
					text = item.disabled or item.detail or "",
					mono = item.disabled == nil,
					tone = if item.disabled then "dim" else "secondary",
					size = if item.disabled then size.small else size.monoSmall,
					height = SEARCH_ROW,
					fill = true,
					alignX = Enum.TextXAlignment.Right,
					layoutOrder = 3,
				}),
			})
		end
		if #matches == 0 then
			rows.None = e(Controls.Text, { text = "(no match)", tone = "dim", size = size.secondary, height = SEARCH_ROW })
		end
		local visible = math.max(1, math.min(#matches, props.maxRows or 8))
		popup = ReactRoblox.createPortal({
			SearchPopup = e("Frame", {
				Size = UDim2.fromOffset(placement.width, visible * SEARCH_ROW + 12),
				Position = UDim2.fromOffset(placement.x, placement.y),
				AnchorPoint = Vector2.new(0, if placement.above then 1 else 0),
				BackgroundColor3 = color.panel,
				BorderSizePixel = 0,
				ZIndex = 2,
			}, {
				Corner = Controls.corner(Theme.radius.large),
				Stroke = Controls.outline(color.strongOutline),
				Padding = Controls.padding(6, 6),
				List = e("ScrollingFrame", scroller({ Size = UDim2.fromScale(1, 1) }), rows),
			}),
		}, overlay)
	end

	return e("Frame", {
		Size = if props.width
			then UDim2.fromOffset(props.width, space.control)
			elseif props.fill then UDim2.fromOffset(0, space.control)
			else UDim2.new(1, 0, 0, space.control),
		BackgroundColor3 = color.raised,
		BorderSizePixel = 0,
		LayoutOrder = props.layoutOrder,
	}, {
		Flex = if props.fill then fillFlex() else nil,
		Corner = Controls.corner(),
		Stroke = Controls.outline(if open then color.strongOutline else color.outline),
		Glyph = e(Glyphs.Glyph, {
			name = "search",
			color = color.dim,
			size = 14,
			position = UDim2.new(0, 9, 0.5, 0),
			anchorPoint = Vector2.new(0, 0.5),
		}),
		Hint = if props.hint and text == ""
			then e("TextLabel", {
				Text = props.hint,
				Size = UDim2.fromOffset(0, space.control),
				AutomaticSize = Enum.AutomaticSize.X,
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -10, 0, 0),
				BackgroundTransparency = 1,
				FontFace = font.body,
				TextSize = size.small,
				TextColor3 = color.dim,
			})
			else nil,
		Box = e("TextBox", {
			ref = function(box: TextBox?)
				boxRef.current = box
				if box then
					box:SetAttribute(FIELD_TAG, true)
				end
			end,
			Text = text,
			PlaceholderText = props.placeholder or "search",
			PlaceholderColor3 = color.dim,
			Size = UDim2.new(1, -30, 1, 0),
			Position = UDim2.fromOffset(28, 0),
			BackgroundTransparency = 1,
			ClearTextOnFocus = false,
			FontFace = font.mono,
			TextSize = size.monoSmall,
			TextColor3 = color.text,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ClipsDescendants = true,
			[React.Change.Text] = function(box: TextBox)
				local cleaned = string.gsub(string.gsub(box.Text, "\t", ""), "`", "")
				if cleaned ~= box.Text then
					box.Text = cleaned
					return
				end
				if cleaned ~= text then
					setText(cleaned)
					setHighlight(1)
				end
			end,
			[React.Event.InputBegan] = notePress,
			[React.Event.Focused] = function(box: TextBox)
				closeToken.current += 1
				scrollIntoView(box)
				place()
				setOpen(true)
			end,
			[React.Event.FocusLost] = function(_box: TextBox, enterPressed: boolean)
				if enterPressed then
					local current = latest.current
					pick(current.matches[current.selected])
					return
				end
				-- Late, so a click on a row lands before the list goes away.
				closeToken.current += 1
				local token = closeToken.current
				task.delay(0.25, function()
					if closeToken.current == token then
						setOpen(false)
					end
				end)
			end,
		}),
		Popup = popup,
	})
end

-- One tab in the left rail: its glyph (or a short text label where no glyph exists), lit when active,
-- with its name in a tooltip beside the rail on hover so a tab is never a mystery.
function Controls.RailItem(props: {
	label: string,
	glyph: string?,
	short: string?,
	active: boolean,
	onActivated: () -> (),
	layoutOrder: number?,
})
	local hovered, setHovered = React.useState(false)
	local ink = if props.active or hovered then color.text else color.dim
	local glyph = props.glyph
	return e("TextButton", {
		Text = "",
		Size = UDim2.fromOffset(36, 36),
		LayoutOrder = props.layoutOrder,
		BackgroundColor3 = color.hover,
		BackgroundTransparency = if props.active then 0 elseif hovered then 0.5 else 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		[React.Event.Activated] = function()
			UISound.play("confirm")
			props.onActivated()
		end,
		[React.Event.MouseEnter] = function()
			setHovered(true)
		end,
		[React.Event.MouseLeave] = function()
			setHovered(false)
		end,
	}, {
		Corner = Controls.corner(),
		Icon = if glyph and Glyphs.has(glyph)
			then e(Glyphs.Glyph, {
				name = glyph,
				color = ink,
				size = 20,
				thickness = 1.6,
				position = UDim2.fromScale(0.5, 0.5),
				anchorPoint = Vector2.new(0.5, 0.5),
			})
			else e(Controls.Text, {
				text = props.short or string.sub(props.label, 1, 3),
				color = ink,
				medium = true,
				size = size.small,
				height = 36,
				alignX = Enum.TextXAlignment.Center,
			}),
		Tip = if hovered
			then e("TextLabel", {
				Text = props.label,
				Size = UDim2.fromOffset(0, 26),
				AutomaticSize = Enum.AutomaticSize.X,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(1, 12, 0.5, 0),
				BackgroundColor3 = color.raised,
				BorderSizePixel = 0,
				FontFace = font.medium,
				TextSize = size.secondary,
				TextColor3 = color.text,
				ZIndex = 50,
			}, {
				Padding = Controls.padding(9),
				Corner = Controls.corner(),
				Stroke = Controls.outline(color.strongOutline),
			})
			else nil,
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
