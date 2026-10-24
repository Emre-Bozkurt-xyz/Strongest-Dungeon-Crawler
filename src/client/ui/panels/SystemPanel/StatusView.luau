--!strict
-- The character sheet, in two tabs.
--
-- STATUS is the at-a-glance view: who you are (level, class, title), your vitals, and your five
-- attributes, which are where points are spent. STATS holds every number, grouped, for when you want
-- the detail. Raw stats on the first view were clutter; the build and the vitals are what a glance is
-- for.
--
-- Keeps every element of the hand-built panel (docs/ui/SystemPanelOTS.png) -- level, class, title,
-- the HP/MP/stamina band, the five attributes and the available points. Laid out in logical pixels
-- (PanelRegistry gives the surface `logicalWidth`).
--
-- Details carried over on purpose:
--   * an attribute cell is itself the button: clicking it spends a point. The "+" only shows that it
--     can be clicked, and only while there are points to spend.
--   * Level, class and title are placeholders until a progression system feeds them, but they are
--     part of the layout, so they show level 1 and "None" rather than being left out.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local PanelShell = require(script.Parent.Parent.Parent.components.PanelShell)
local StatList = require(script.Parent.Parent.Parent.components.StatList)
local VitalsBlock = require(script.Parent.Parent.Parent.components.VitalsBlock)
local ThemeContext = require(script.Parent.Parent.Parent.hooks.ThemeContext)
local useSpring = require(script.Parent.Parent.Parent.hooks.useSpring)
local UISound = require(script.Parent.Parent.Parent.UISound)

local Selector = require(script.Parent.Parent.Parent.selectors.systemStatus)

local e = React.createElement

export type Tab = "status" | "stats"

export type Props = {
	view: Selector.SystemView,
	tab: Tab,
	onTab: (tab: Tab) -> (),
	onSpend: (attributeId: string) -> (),
}

local StatusView = {}

-- Logical pixels.
local TITLE_HEIGHT = 34
local IDENTITY_HEIGHT = 120
local VITALS_SCALE = 1.55
local ATTRIBUTE_HEIGHT = 92
local STAT_ROW_HEIGHT = 22

-- Widths fit the labels at the title size; fixed so the underline can be scaled to the tab.
local TABS: { { id: Tab, label: string, width: number } } = {
	{ id = "status", label = "STATUS", width = 140 },
	{ id = "stats", label = "STATS", width = 116 },
}

local function Caption(props: { text: string, size: UDim2, position: UDim2?, alignX: Enum.TextXAlignment? })
	local theme = ThemeContext.useTheme()
	return e("TextLabel", {
		Text = props.text,
		Size = props.size,
		Position = props.position,
		BackgroundTransparency = 1,
		FontFace = theme.face.display,
		TextSize = theme.type.label,
		TextColor3 = theme.color.textMuted,
		TextXAlignment = props.alignX or Enum.TextXAlignment.Left,
	})
end

-- One tab in the title row, drawn as a panel title: the current tab is the lit heading with its marker
-- and underline, the other a dim title that lights on hover.
local function TabButton(props: {
	label: string,
	width: number,
	active: boolean,
	layoutOrder: number,
	onActivated: () -> (),
})
	local theme = ThemeContext.useTheme()
	local hovered, setHovered = React.useState(false)
	local lit = props.active or hovered
	local underline = useSpring(if props.active then 1 else 0, theme.motion.snap)

	return e("TextButton", {
		Text = "",
		Size = UDim2.new(0, props.width, 1, 0),
		LayoutOrder = props.layoutOrder,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		[React.Event.Activated] = function()
			if not props.active then
				UISound.play("confirm")
				props.onActivated()
			end
		end,
		[React.Event.MouseEnter] = function()
			setHovered(true)
			if not props.active then
				UISound.play("hover")
			end
		end,
		[React.Event.MouseLeave] = function()
			setHovered(false)
		end,
	}, {
		Row = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
		}, {
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 10),
			}),
			MarkerCell = e("Frame", {
				Size = UDim2.fromOffset(10, 10),
				LayoutOrder = 1,
				BackgroundTransparency = 1,
			}, {
				Marker = e("Frame", {
					Size = UDim2.fromOffset(7, 7),
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Rotation = 45,
					BackgroundColor3 = theme.color.stroke,
					BackgroundTransparency = if props.active then 0 else 0.7,
					BorderSizePixel = 0,
				}),
			}),
			Label = e("TextLabel", {
				Text = props.label,
				Size = UDim2.fromScale(0, 1),
				AutomaticSize = Enum.AutomaticSize.X,
				LayoutOrder = 2,
				BackgroundTransparency = 1,
				FontFace = theme.face.display,
				TextSize = theme.type.title,
				TextColor3 = if lit then theme.color.textHeading else theme.color.textMuted,
			}),
		}),
		-- The rule under the current tab, growing in when it becomes current.
		Underline = e("Frame", {
			Size = underline:map(function(v: number)
				return UDim2.new(v, 0, 0, 1)
			end),
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			BackgroundColor3 = theme.color.stroke,
			BorderSizePixel = 0,
		}, {
			Fade = e("UIGradient", {
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.1),
					NumberSequenceKeypoint.new(1, 0.8),
				}),
			}),
		}),
	})
end

local function TitleRow(props: { tab: Tab, onTab: (tab: Tab) -> (), points: number })
	local theme = ThemeContext.useTheme()
	local tabs: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 26),
		}),
	}
	for index, tab in ipairs(TABS) do
		tabs[tab.id] = e(TabButton, {
			label = tab.label,
			width = tab.width,
			active = props.tab == tab.id,
			layoutOrder = index,
			onActivated = function()
				props.onTab(tab.id)
			end,
		})
	end

	return e("Frame", {
		Size = UDim2.new(1, 0, 0, TITLE_HEIGHT),
		LayoutOrder = 1,
		BackgroundTransparency = 1,
	}, {
		Tabs = e("Frame", {
			Size = UDim2.fromScale(0.7, 1),
			BackgroundTransparency = 1,
		}, tabs),
		-- Shown on either tab, in accent, so points waiting to be spent are never missed.
		Points = if props.points > 0
			then e("TextLabel", {
				Text = `<font face="Michroma" size="{theme.type.label}" color="#{theme.color.textMuted:ToHex()}">POINTS  </font>{props.points}`,
				RichText = true,
				Size = UDim2.fromScale(0.3, 1),
				Position = UDim2.fromScale(0.7, 0),
				BackgroundTransparency = 1,
				FontFace = theme.face.mono,
				TextSize = theme.type.title,
				TextColor3 = theme.color.accent,
				TextXAlignment = Enum.TextXAlignment.Right,
			})
			else nil,
		Rule = e("Frame", {
			Size = UDim2.new(1, 0, 0, 1),
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			BackgroundColor3 = theme.color.stroke,
			BackgroundTransparency = theme.chrome.edgeTransparency,
			BorderSizePixel = 0,
		}),
	})
end

-- Level large at the left; class and title as caption/value pairs beside it, past a hairline.
local function Identity(props: { identity: Selector.IdentityView })
	local theme = ThemeContext.useTheme()
	local identity = props.identity

	local function pair(caption: string, value: string, y: number)
		return e("Frame", {
			Size = UDim2.new(1, 0, 0, 30),
			Position = UDim2.fromOffset(0, y),
			BackgroundTransparency = 1,
		}, {
			Caption = e(Caption, { text = caption, size = UDim2.new(0, 60, 1, 0) }),
			Value = e("TextLabel", {
				Text = value,
				Size = UDim2.new(1, -60, 1, 0),
				Position = UDim2.fromOffset(60, 0),
				BackgroundTransparency = 1,
				FontFace = theme.face.bodyBold,
				TextSize = theme.type.title,
				TextColor3 = theme.color.textPrimary,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
		})
	end

	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		LevelCaption = e(Caption, {
			text = "LEVEL",
			size = UDim2.fromOffset(120, 16),
			position = UDim2.fromOffset(0, 18),
		}),
		LevelValue = e("TextLabel", {
			Text = tostring(identity.level or 1),
			Size = UDim2.fromOffset(120, 64),
			Position = UDim2.fromOffset(0, 38),
			BackgroundTransparency = 1,
			FontFace = theme.face.display,
			TextSize = 58,
			TextColor3 = theme.color.textHeading,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Divider = e("Frame", {
			Size = UDim2.new(0, 1, 1, -28),
			Position = UDim2.fromOffset(128, 14),
			BackgroundColor3 = theme.color.stroke,
			BackgroundTransparency = theme.chrome.edgeTransparency,
			BorderSizePixel = 0,
		}),
		Pairs = e("Frame", {
			Size = UDim2.new(1, -148, 1, 0),
			Position = UDim2.fromOffset(148, 0),
			BackgroundTransparency = 1,
		}, {
			Class = pair("CLASS", identity.class or "None", 28),
			Title = pair("TITLE", identity.title or "None", 62),
		}),
	})
end

-- One attribute as a cell: its icon and short name, the value large, any bonus beside it. The whole
-- cell is the button; it lights on hover while there are points to spend.
local function AttributeCell(props: {
	row: Selector.AttributeRow,
	layoutOrder: number,
	enabled: boolean,
	onSpend: (attributeId: string) -> (),
})
	local theme = ThemeContext.useTheme()
	local row = props.row
	local hovered, setHovered = React.useState(false)
	local glow = useSpring(if hovered and props.enabled then 1 else 0, theme.motion.snap)

	local value = tostring(row.base)
	if row.bonus ~= 0 then
		value ..= ` <font color="#{theme.color.success:ToHex()}" size="{theme.type.small}">+{row.bonus}</font>`
	end

	return e("TextButton", {
		Text = "",
		Size = UDim2.fromScale(0, 1),
		LayoutOrder = props.layoutOrder,
		BackgroundColor3 = theme.color.accent,
		BackgroundTransparency = glow:map(function(v: number)
			return 1 - 0.12 * v
		end),
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Active = props.enabled,
		[React.Event.Activated] = function()
			if props.enabled then
				UISound.play("confirm")
				props.onSpend(row.id)
			end
		end,
		[React.Event.MouseEnter] = function()
			setHovered(true)
			if props.enabled then
				UISound.play("hover")
			end
		end,
		[React.Event.MouseLeave] = function()
			setHovered(false)
		end,
	}, {
		Flex = e("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }),
		Hairline = e("UIStroke", {
			Color = theme.color.stroke,
			Thickness = 1,
			Transparency = glow:map(function(v: number)
				return 0.8 - 0.5 * v
			end),
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		}),
		Icon = e("ImageLabel", {
			Image = row.icon,
			Size = UDim2.fromOffset(18, 18),
			Position = UDim2.fromOffset(10, 10),
			BackgroundTransparency = 1,
			ImageColor3 = theme.color.textPrimary,
			ScaleType = Enum.ScaleType.Fit,
		}),
		Short = e("TextLabel", {
			Text = row.short,
			Size = UDim2.fromOffset(60, 18),
			Position = UDim2.fromOffset(34, 10),
			BackgroundTransparency = 1,
			FontFace = theme.face.display,
			TextSize = theme.type.small,
			TextColor3 = theme.color.textHeading,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Value = e("TextLabel", {
			Text = value,
			RichText = true,
			Size = UDim2.new(1, -20, 0, 34),
			Position = UDim2.new(0, 10, 1, -44),
			BackgroundTransparency = 1,
			FontFace = theme.face.mono,
			TextSize = 28,
			TextColor3 = theme.color.textPrimary,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Plus = if props.enabled
			then e("TextLabel", {
				Text = "+",
				Size = UDim2.fromOffset(20, 20),
				AnchorPoint = Vector2.new(1, 1),
				Position = UDim2.new(1, -8, 1, -10),
				BackgroundTransparency = 1,
				FontFace = theme.face.mono,
				TextSize = theme.type.body,
				TextColor3 = theme.color.accent,
			}, {
				Stroke = e("UIStroke", {
					Color = theme.color.accent,
					Thickness = 1,
					Transparency = glow:map(function(v: number)
						return 0.5 - 0.5 * v
					end),
					ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				}),
			})
			else nil,
	})
end

local function StatusTab(props: { view: Selector.SystemView, onSpend: (attributeId: string) -> () })
	local theme = ThemeContext.useTheme()
	local view = props.view

	local cells: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 10),
		}),
	}
	for index, row in ipairs(view.attributes) do
		cells[row.id] = e(AttributeCell, {
			row = row,
			layoutOrder = index,
			enabled = view.availableAP > 0,
			onSpend = props.onSpend,
		})
	end

	return e("Frame", {
		Size = UDim2.fromScale(1, 0),
		LayoutOrder = 2,
		BackgroundTransparency = 1,
	}, {
		Flex = e("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }),
		-- Identity and vitals share the space above the attributes, centred in it.
		Top = e("Frame", {
			Size = UDim2.new(1, 0, 1, -(ATTRIBUTE_HEIGHT + 44)),
			BackgroundTransparency = 1,
		}, {
			Identity = e("Frame", {
				Size = UDim2.fromOffset(330, IDENTITY_HEIGHT),
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromScale(0, 0.5),
				BackgroundTransparency = 1,
			}, {
				View = e(Identity, { identity = view.identity }),
			}),
			-- The HUD strip's vitals, scaled up: the same block, so the two always agree.
			Vitals = e("Frame", {
				Size = UDim2.fromOffset((728 - 360) / VITALS_SCALE, VitalsBlock.HEIGHT),
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.fromScale(1, 0.5),
				BackgroundTransparency = 1,
			}, {
				Scale = e("UIScale", { Scale = VITALS_SCALE }),
				Block = e(VitalsBlock.render, { vitals = view.vitals }),
			}),
		}),
		Divider = e("Frame", {
			Size = UDim2.new(1, 0, 0, 1),
			Position = UDim2.new(0, 0, 1, -(ATTRIBUTE_HEIGHT + 42)),
			BackgroundColor3 = theme.color.stroke,
			BackgroundTransparency = theme.chrome.edgeTransparency,
			BorderSizePixel = 0,
		}),
		AttributesCaption = e(Caption, {
			text = "ATTRIBUTES",
			size = UDim2.new(1, 0, 0, 20),
			position = UDim2.new(0, 0, 1, -(ATTRIBUTE_HEIGHT + 30)),
		}),
		Attributes = e("Frame", {
			Size = UDim2.new(1, 0, 0, ATTRIBUTE_HEIGHT),
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			BackgroundTransparency = 1,
		}, cells),
	})
end

local function StatColumn(props: { layoutOrder: number, children: any })
	local children: { [string]: any } = {
		Flex = e("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }),
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 14),
		}),
	}
	for key, child in pairs(props.children) do
		children[key] = child
	end
	return e("Frame", {
		Size = UDim2.fromScale(0, 1),
		LayoutOrder = props.layoutOrder,
		BackgroundTransparency = 1,
	}, children)
end

local function statSection(title: string, rows: { Selector.StatRow }, layoutOrder: number): any
	if #rows == 0 then
		return nil
	end
	local children: { [string]: any } = {}
	for index, stat in ipairs(rows) do
		children[`Stat{index}`] = e(StatList.Row, {
			label = stat.label,
			value = stat.value,
			role = "BodyText",
			layoutOrder = index,
			rowHeight = STAT_ROW_HEIGHT,
			labelWidth = 0.6,
		})
	end
	return e(StatList.Section, {
		title = title,
		layoutOrder = layoutOrder,
		rowHeight = STAT_ROW_HEIGHT,
		children = children,
	})
end

-- Every number, grouped. Pools come from the vitals; attributes show what is base and what is bonus.
local function StatsTab(props: { view: Selector.SystemView })
	local view = props.view

	local pools: { Selector.StatRow } = {}
	for _, vital in ipairs(view.vitals) do
		table.insert(pools, { label = `Max {vital.label}`, value = tostring(math.floor(vital.max)) })
	end
	local attributes: { Selector.StatRow } = {}
	for _, row in ipairs(view.attributes) do
		table.insert(attributes, {
			label = row.label,
			value = if row.bonus ~= 0 then `{row.total} ({row.base}+{row.bonus})` else tostring(row.total),
		})
	end

	return e("Frame", {
		Size = UDim2.fromScale(1, 0),
		LayoutOrder = 2,
		BackgroundTransparency = 1,
	}, {
		Flex = e("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }),
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 28),
		}),
		Left = e(StatColumn, { layoutOrder = 1 }, {
			Pools = statSection("Pools", pools, 1),
			Recovery = statSection("Recovery", view.recoveryStats, 2),
		}),
		Middle = e(StatColumn, { layoutOrder = 2 }, {
			Offense = statSection("Offense", view.combatStats, 1),
		}),
		Right = e(StatColumn, { layoutOrder = 3 }, {
			Attributes = statSection("Attributes", attributes, 1),
		}),
	})
end

function StatusView.render(props: Props)
	local view = props.view

	return e(PanelShell, { padding = 20, gap = 14 }, {
		Title = e(TitleRow, { tab = props.tab, onTab = props.onTab, points = view.availableAP }),
		Body = if props.tab == "stats"
			then e(StatsTab, { view = view })
			else e(StatusTab, { view = view, onSpend = props.onSpend }),
	})
end

return StatusView
