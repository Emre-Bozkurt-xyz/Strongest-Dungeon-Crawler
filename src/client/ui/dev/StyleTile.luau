--!strict
-- Style tile for the System direction (docs/tasks/ui-design-pass.md): one specimen surface showing
-- palette, type, chrome, controls and one motion sample, to settle the visual language before any
-- real panel is rebuilt.
--
-- Deliberately self-contained, with its own prototype tokens rather than the live theme, so it can
-- change freely while the direction is argued over. Once it is agreed the tokens move into a theme
-- and the chrome pieces (Brackets, HeaderRule) become the skinnable chrome parts.
--
-- Authored on an 864-unit-wide canvas, from when it scaled the System panel's raw 1296px canvas up
-- by 1.5. That surface is now laid out at 768 logical pixels, so the tile scales down to fit it.
--
-- Studio only. F7 (or "Tile" in the F6 tuner) swaps it in for the System panel's content.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local DevFlags = require(script.Parent.DevFlags)
local useSpring = require(script.Parent.Parent.hooks.useSpring)

local e = React.createElement

local SCALE = 768 / 864

-- Prototype palette. Light on near-black: the System is projected, so surfaces are dark and
-- translucent and everything meaningful is drawn in light.
local C = {
	void = Color3.fromRGB(4, 9, 18),
	deep = Color3.fromRGB(11, 26, 46),
	line = Color3.fromRGB(73, 210, 255),
	lineDim = Color3.fromRGB(31, 110, 150),
	glow = Color3.fromRGB(168, 240, 255),
	ink = Color3.fromRGB(232, 247, 255),
	inkMuted = Color3.fromRGB(126, 166, 189),
	inkFaint = Color3.fromRGB(74, 106, 128),
	alert = Color3.fromRGB(255, 77, 97),
	warn = Color3.fromRGB(255, 192, 77),
	ok = Color3.fromRGB(92, 255, 176),
}

local RARITY = {
	normal = Color3.fromRGB(185, 198, 208),
	magic = Color3.fromRGB(79, 163, 255),
	rare = Color3.fromRGB(255, 210, 90),
	unique = Color3.fromRGB(255, 138, 61),
}

local TITILLIUM = Font.fromEnum(Enum.Font.TitilliumWeb).Family
local FONT = {
	display = Font.fromEnum(Enum.Font.Michroma),
	body = Font.new(TITILLIUM, Enum.FontWeight.Regular),
	bodyBold = Font.new(TITILLIUM, Enum.FontWeight.Bold),
	mono = Font.fromEnum(Enum.Font.RobotoMono),
}

-- Type scale, in logical (≈ screen) pixels.
local TYPE = {
	label = 11,
	small = 13,
	body = 16,
	title = 18,
	display = 22,
}

local MOTION = {
	snap = { frequency = 6, damping = 1 },
	settle = { frequency = 3, damping = 0.72 },
}

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function Label(props: {
	text: string,
	font: Font,
	size: number,
	color: Color3?,
	position: UDim2?,
	frameSize: UDim2?,
	alignX: Enum.TextXAlignment?,
	transparency: any?,
	layoutOrder: number?,
})
	return e("TextLabel", {
		Text = props.text,
		FontFace = props.font,
		TextSize = props.size,
		TextColor3 = props.color or C.ink,
		TextTransparency = props.transparency,
		Position = props.position,
		Size = props.frameSize or UDim2.new(1, 0, 0, props.size + 6),
		LayoutOrder = props.layoutOrder,
		BackgroundTransparency = 1,
		TextXAlignment = props.alignX or Enum.TextXAlignment.Left,
	})
end

local function SectionLabel(props: { text: string, layoutOrder: number })
	return e(Label, {
		text = props.text,
		font = FONT.display,
		size = TYPE.label,
		color = C.inkMuted,
		layoutOrder = props.layoutOrder,
	})
end

-- Four L-shaped corners instead of a full border: the shape reads as a projected frame, and the
-- corners are what animate when a window materialises. `progress` (0..1) slides them from the centre
-- out to the corners.
local function Brackets(props: {
	color: Color3,
	length: number,
	thickness: number,
	progress: any?,
	edgeTransparency: number?,
})
	local children: { [string]: any } = {}
	for _, corner in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
		local cx, cy = corner[1], corner[2]
		local position = if props.progress
			then props.progress:map(function(p: number)
				return UDim2.fromScale(lerp(0.5, cx, p), lerp(0.5, cy, p))
			end)
			else UDim2.fromScale(cx, cy)
		children[`Corner{cx}{cy}`] = e("Frame", {
			Size = UDim2.fromOffset(props.length, props.length),
			AnchorPoint = Vector2.new(cx, cy),
			Position = position,
			BackgroundTransparency = 1,
			ZIndex = 20,
		}, {
			Horizontal = e("Frame", {
				Size = UDim2.new(1, 0, 0, props.thickness),
				AnchorPoint = Vector2.new(cx, cy),
				Position = UDim2.fromScale(cx, cy),
				BackgroundColor3 = props.color,
				BorderSizePixel = 0,
			}),
			Vertical = e("Frame", {
				Size = UDim2.new(0, props.thickness, 1, 0),
				AnchorPoint = Vector2.new(cx, cy),
				Position = UDim2.fromScale(cx, cy),
				BackgroundColor3 = props.color,
				BorderSizePixel = 0,
			}),
		})
	end
	-- A hairline between the corners, so the frame is complete but the corners carry it.
	children.Edge = e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 19,
	}, {
		Stroke = e("UIStroke", {
			Color = props.color,
			Thickness = 1,
			Transparency = if props.progress
				then props.progress:map(function(p: number)
					return lerp(1, props.edgeTransparency or 0.78, math.clamp((p - 0.6) / 0.4, 0, 1))
				end)
				else props.edgeTransparency or 0.78,
		}),
	})
	return e("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, children)
end

-- Section header: a lit marker, the title, a rule running to the edge, and optional meta on the right.
local function HeaderRule(props: { title: string, meta: string?, size: number, transparency: any? })
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, props.size + 8),
		BackgroundTransparency = 1,
	}, {
		Marker = e("Frame", {
			Size = UDim2.fromOffset(6, 6),
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			Rotation = 45,
			BackgroundColor3 = C.line,
			BackgroundTransparency = props.transparency,
			BorderSizePixel = 0,
		}),
		Title = e("TextLabel", {
			Text = props.title,
			FontFace = FONT.display,
			TextSize = props.size,
			TextColor3 = C.ink,
			TextTransparency = props.transparency,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromScale(0, 1),
			Position = UDim2.fromOffset(15, 0),
			BackgroundTransparency = 1,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Rule = e("Frame", {
			Size = UDim2.new(0.5, 0, 0, 1),
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, if props.meta then -86 else 0, 0.5, 0),
			BackgroundColor3 = C.line,
			BackgroundTransparency = props.transparency,
			BorderSizePixel = 0,
		}, {
			Fade = e("UIGradient", {
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.4, 0.45),
					NumberSequenceKeypoint.new(1, 0.15),
				}),
			}),
		}),
		Meta = if props.meta
			then e("TextLabel", {
				Text = props.meta,
				FontFace = FONT.mono,
				TextSize = TYPE.label,
				TextColor3 = C.inkFaint,
				TextTransparency = props.transparency,
				Size = UDim2.new(0, 80, 1, 0),
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromScale(1, 0),
				BackgroundTransparency = 1,
				TextXAlignment = Enum.TextXAlignment.Right,
			})
			else nil,
	})
end

local function Swatch(props: { name: string, color: Color3, layoutOrder: number })
	return e("Frame", {
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
	}, {
		Chip = e("Frame", {
			Size = UDim2.fromOffset(16, 16),
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			BackgroundColor3 = props.color,
			BorderSizePixel = 0,
		}, {
			Stroke = e("UIStroke", { Color = C.lineDim, Thickness = 1, Transparency = 0.3 }),
		}),
		Name = e(Label, {
			text = props.name,
			font = FONT.mono,
			size = TYPE.label,
			color = C.inkMuted,
			position = UDim2.fromOffset(24, 0),
			frameSize = UDim2.new(1, -24, 1, 0),
		}),
	})
end

-- An item slot: dark well, dim outline, corner ticks, rarity as a lit floor rather than a coloured
-- box, so a wall of slots stays calm and the rare ones still catch the eye.
local function Slot(props: { rarity: string?, selected: boolean?, layoutOrder: number })
	local hovered, setHovered = React.useState(false)
	local lift = useSpring(if hovered or props.selected then 1 else 0, MOTION.snap)
	local tint = if props.rarity then RARITY[props.rarity] else nil
	local lit = props.selected or hovered

	return e("TextButton", {
		Text = "",
		AutoButtonColor = false,
		Size = UDim2.fromOffset(48, 48),
		LayoutOrder = props.layoutOrder,
		BackgroundColor3 = C.deep,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		[React.Event.MouseEnter] = function()
			setHovered(true)
		end,
		[React.Event.MouseLeave] = function()
			setHovered(false)
		end,
	}, {
		Scale = e("UIScale", {
			Scale = lift:map(function(v: number)
				return 1 + 0.06 * v
			end),
		}),
		Outline = e("UIStroke", {
			Color = if lit then C.line else C.lineDim,
			Thickness = if props.selected then 2 else 1,
			Transparency = if lit then 0 else 0.35,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		Ticks = e(Brackets, {
			color = if lit then C.glow else C.line,
			length = 8,
			thickness = 2,
			edgeTransparency = 1,
		}),
		Glow = if tint
			then e("Frame", {
				Size = UDim2.fromScale(1, 0.6),
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				BackgroundColor3 = tint,
				BorderSizePixel = 0,
			}, {
				Fade = e("UIGradient", {
					Rotation = -90,
					Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 0.55),
						NumberSequenceKeypoint.new(1, 1),
					}),
				}),
			})
			else nil,
		Floor = if tint
			then e("Frame", {
				Size = UDim2.new(1, 0, 0, 2),
				AnchorPoint = Vector2.new(0, 1),
				Position = UDim2.fromScale(0, 1),
				BackgroundColor3 = tint,
				BorderSizePixel = 0,
			})
			else nil,
		-- Placeholder glyph until item icons exist.
		Glyph = if tint
			then e("Frame", {
				Size = UDim2.fromOffset(14, 14),
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.45),
				Rotation = 45,
				BackgroundColor3 = tint,
				BackgroundTransparency = 0.15,
				BorderSizePixel = 0,
			})
			else nil,
	})
end

local function Button(props: { text: string, variant: "primary" | "secondary" | "disabled", layoutOrder: number })
	local hovered, setHovered = React.useState(false)
	local disabled = props.variant == "disabled"
	local glow = useSpring(if hovered and not disabled then 1 else 0, MOTION.snap)
	local primary = props.variant == "primary"

	return e("TextButton", {
		Text = props.text,
		FontFace = FONT.display,
		TextSize = TYPE.label + 1,
		TextColor3 = if disabled then C.inkFaint elseif primary then C.void else C.ink,
		AutoButtonColor = false,
		Size = UDim2.fromOffset(84, 30),
		LayoutOrder = props.layoutOrder,
		BackgroundColor3 = C.line,
		BackgroundTransparency = if primary
			then glow:map(function(v: number)
				return lerp(0.08, 0, v)
			end)
			else glow:map(function(v: number)
				return lerp(1, 0.82, v)
			end),
		BorderSizePixel = 0,
		Active = not disabled,
		[React.Event.MouseEnter] = function()
			setHovered(true)
		end,
		[React.Event.MouseLeave] = function()
			setHovered(false)
		end,
	}, {
		Outline = e("UIStroke", {
			Color = if disabled then C.inkFaint else C.line,
			Thickness = 1,
			Transparency = if disabled then 0.5 else 0,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		Scale = e("UIScale", {
			Scale = glow:map(function(v: number)
				return 1 + 0.04 * v
			end),
		}),
	})
end

-- Segmented rather than continuous: discrete cells read as a readout from the System, not a health
-- bar from a generic game.
local function SegmentedGauge(props: {
	label: string,
	value: number,
	max: number,
	color: Color3,
	segments: number,
	layoutOrder: number,
})
	local filled = math.floor(props.value / props.max * props.segments + 0.5)
	local cells: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 2),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for i = 1, props.segments do
		cells[`Cell{i}`] = e("Frame", {
			Size = UDim2.new(1 / props.segments, -2, 1, 0),
			LayoutOrder = i,
			BackgroundColor3 = if i <= filled then props.color else C.deep,
			BackgroundTransparency = if i <= filled then 0 else 0.2,
			BorderSizePixel = 0,
		})
	end
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
	}, {
		Name = e(Label, {
			text = props.label,
			font = FONT.display,
			size = TYPE.label,
			color = C.inkMuted,
			frameSize = UDim2.new(0.5, 0, 0, 16),
		}),
		Value = e(Label, {
			text = `{props.value} / {props.max}`,
			font = FONT.mono,
			size = TYPE.small,
			position = UDim2.fromScale(0.5, 0),
			frameSize = UDim2.new(0.5, 0, 0, 16),
			alignX = Enum.TextXAlignment.Right,
		}),
		Track = e("Frame", {
			Size = UDim2.new(1, 0, 0, 10),
			Position = UDim2.fromOffset(0, 21),
			BackgroundTransparency = 1,
		}, cells),
	})
end

-- A System message, materialising on a loop: the corners fly out from the centre on the settle
-- spring, the hairline joins them, and only then does the content fade up.
local function Notification()
	local progress, snapTo = useSpring(1, MOTION.settle, 0)
	React.useEffect(function()
		local alive = true
		task.spawn(function()
			while alive do
				task.wait(3.2)
				if alive then
					snapTo(0)
				end
			end
		end)
		return function()
			alive = false
		end
	end, {})

	local content = progress:map(function(p: number)
		return 1 - math.clamp((p - 0.55) / 0.45, 0, 1)
	end)

	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.void,
		BackgroundTransparency = progress:map(function(p: number)
			return lerp(1, 0.15, math.clamp(p, 0, 1))
		end),
		BorderSizePixel = 0,
	}, {
		-- Chrome frames the card, so it must not sit under the content's UIPadding: padding applies to
		-- every child, and the corners would be pushed inward onto the text they are meant to frame.
		Brackets = e(Brackets, { color = C.line, length = 16, thickness = 2, progress = progress }),
		Body = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
		}, {
			Padding = e("UIPadding", {
				PaddingTop = UDim.new(0, 14),
				PaddingBottom = UDim.new(0, 14),
				PaddingLeft = UDim.new(0, 18),
				PaddingRight = UDim.new(0, 18),
			}),
			Header = e(HeaderRule, { title = "NOTIFICATION", size = TYPE.label + 1, transparency = content }),
			Alert = e("Frame", {
				Size = UDim2.fromOffset(26, 26),
				Position = UDim2.fromOffset(0, 38),
				BackgroundTransparency = 1,
			}, {
				Stroke = e("UIStroke", { Color = C.line, Thickness = 2, Transparency = content }),
				Mark = e(Label, {
					text = "!",
					font = FONT.display,
					size = TYPE.title,
					color = C.line,
					transparency = content,
					frameSize = UDim2.fromScale(1, 1),
					alignX = Enum.TextXAlignment.Center,
				}),
			}),
			Message = e(Label, {
				text = "You have acquired an item.",
				font = FONT.bodyBold,
				size = TYPE.body,
				transparency = content,
				position = UDim2.fromOffset(36, 36),
				frameSize = UDim2.new(1, -36, 0, 20),
			}),
			Item = e(Label, {
				text = "Iron Sword",
				font = FONT.bodyBold,
				size = TYPE.body,
				color = RARITY.rare,
				transparency = content,
				position = UDim2.fromOffset(36, 58),
				frameSize = UDim2.new(1, -36, 0, 20),
			}),
			Hint = e(Label, {
				text = "Rare · Main hand · +12 Phys",
				font = FONT.mono,
				size = TYPE.label,
				color = C.inkMuted,
				transparency = content,
				position = UDim2.fromOffset(36, 82),
				frameSize = UDim2.new(1, -36, 0, 16),
			}),
			Confirm = e("Frame", {
				Size = UDim2.fromOffset(84, 30),
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
			}, {
				Button = e(Button, { text = "CONFIRM", variant = "secondary", layoutOrder = 1 }),
			}),
		}),
	})
end

local function Column(props: { x: number, width: number, children: any })
	local children = table.clone(props.children)
	children.Layout = e("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
	})
	return e("Frame", {
		Position = UDim2.fromOffset(props.x, 54),
		Size = UDim2.new(0, props.width, 1, -70),
		BackgroundTransparency = 1,
	}, children)
end

local function Row(props: { height: number, gap: number, layoutOrder: number, children: any })
	local children = table.clone(props.children)
	children.Layout = e("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, props.gap),
		VerticalAlignment = Enum.VerticalAlignment.Center,
	})
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, props.height),
		BackgroundTransparency = 1,
		LayoutOrder = props.layoutOrder,
	}, children)
end

local function StyleTile()
	local swatches: { [string]: any } = {
		Layout = e("UIGridLayout", {
			CellSize = UDim2.new(1 / 3, -7, 0, 20),
			CellPadding = UDim2.fromOffset(10, 5),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	local swatchList = {
		{ "void", C.void },
		{ "deep", C.deep },
		{ "line", C.line },
		{ "lineDim", C.lineDim },
		{ "glow", C.glow },
		{ "ink", C.ink },
		{ "inkMuted", C.inkMuted },
		{ "alert", C.alert },
		{ "warn", C.warn },
		{ "ok", C.ok },
		{ "magic", RARITY.magic },
		{ "rare", RARITY.rare },
	}
	for index, entry in ipairs(swatchList) do
		swatches[entry[1]] = e(Swatch, { name = entry[1], color = entry[2], layoutOrder = index })
	end

	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.void,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
	}, {
		-- Denser at the top where the header sits, thinning toward the bottom, so the panel reads as
		-- projected light over the world rather than a slab.
		Fade = e("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(1, 0.45),
			}),
		}),
		Brackets = e(Brackets, { color = C.line, length = 40, thickness = 4 }),
		Content = e("Frame", {
			Size = UDim2.fromScale(1 / SCALE, 1 / SCALE),
			BackgroundTransparency = 1,
		}, {
			Scale = e("UIScale", { Scale = SCALE }),
			Title = e("Frame", {
				Position = UDim2.fromOffset(24, 16),
				Size = UDim2.new(1, -48, 0, 28),
				BackgroundTransparency = 1,
			}, {
				Header = e(HeaderRule, { title = "THE SYSTEM", meta = "STYLE TILE v2", size = TYPE.title }),
			}),

			Type = e(Column, { x = 24, width = 250 }, {
				PaletteHead = e(SectionLabel, { text = "PALETTE", layoutOrder = 1 }),
				Palette = e("Frame", {
					Size = UDim2.new(1, 0, 0, 100),
					BackgroundTransparency = 1,
					LayoutOrder = 2,
				}, swatches),
				TypeHead = e(SectionLabel, { text = "TYPE", layoutOrder = 3 }),
				Display = e(Label, {
					text = "STATUS WINDOW",
					font = FONT.display,
					size = TYPE.display,
					color = C.glow,
					layoutOrder = 4,
				}),
				Body = e(Label, { text = "Strength increased by 2.", font = FONT.bodyBold, size = TYPE.body, layoutOrder = 5 }),
				Muted = e(Label, {
					text = "Equip to increase physical damage.",
					font = FONT.body,
					size = TYPE.small,
					color = C.inkMuted,
					layoutOrder = 6,
				}),
				Mono = e(Label, { text = "HP  1,284 / 2,000", font = FONT.mono, size = TYPE.small, layoutOrder = 7 }),
			}),

			Controls = e(Column, { x = 300, width = 262 }, {
				SlotsHead = e(SectionLabel, { text = "SLOTS", layoutOrder = 1 }),
				Slots = e(Row, { height = 54, gap = 5, layoutOrder = 2 }, {
					Normal = e(Slot, { rarity = "normal", layoutOrder = 1 }),
					Magic = e(Slot, { rarity = "magic", selected = true, layoutOrder = 2 }),
					Rare = e(Slot, { rarity = "rare", layoutOrder = 3 }),
					Unique = e(Slot, { rarity = "unique", layoutOrder = 4 }),
					Empty = e(Slot, { layoutOrder = 5 }),
				}),
				ButtonsHead = e(SectionLabel, { text = "BUTTONS", layoutOrder = 3 }),
				Buttons = e(Row, { height = 34, gap = 6, layoutOrder = 4 }, {
					Equip = e(Button, { text = "EQUIP", variant = "primary", layoutOrder = 1 }),
					Drop = e(Button, { text = "DROP", variant = "secondary", layoutOrder = 2 }),
					Use = e(Button, { text = "USE", variant = "disabled", layoutOrder = 3 }),
				}),
				GaugesHead = e(SectionLabel, { text = "GAUGES", layoutOrder = 5 }),
				Health = e(SegmentedGauge, {
					label = "HP",
					value = 1284,
					max = 2000,
					color = C.line,
					segments = 20,
					layoutOrder = 6,
				}),
				Mana = e(SegmentedGauge, {
					label = "MP",
					value = 340,
					max = 400,
					color = RARITY.magic,
					segments = 20,
					layoutOrder = 7,
				}),
			}),

			Motion = e(Column, { x = 590, width = 252 }, {
				MotionHead = e(SectionLabel, { text = "MOTION — MATERIALISE", layoutOrder = 1 }),
				Card = e("Frame", {
					Size = UDim2.fromOffset(252, 170),
					BackgroundTransparency = 1,
					LayoutOrder = 2,
				}, {
					Notification = e(Notification),
				}),
			}),
		}),
	})
end

-- Wraps a panel so F7 swaps the tile in for its content; anything else renders the panel untouched.
local function withStyleTile(Panel: any)
	return function(props: any)
		local showing, setShowing = React.useState(DevFlags.get("styleTile"))
		React.useEffect(function()
			return DevFlags.onChanged(function()
				setShowing(DevFlags.get("styleTile"))
			end)
		end, {})
		if showing then
			return e(StyleTile)
		end
		return e(Panel, props)
	end
end

return {
	StyleTile = StyleTile,
	withStyleTile = withStyleTile,
}
