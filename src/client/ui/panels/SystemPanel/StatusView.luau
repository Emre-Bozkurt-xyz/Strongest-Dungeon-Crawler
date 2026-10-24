--!strict
-- The character status sheet: identity, vitals and combat stats on the left; attributes, the points
-- to spend on them, and recovery stats on the right.
--
-- Keeps every element of the hand-built panel (docs/ui/SystemPanelOTS.png) -- level, class, title,
-- the HP/MP/stamina band, the five attributes and the available points -- laid out across the whole
-- surface in logical pixels (PanelRegistry gives it `logicalWidth`) and in the System's style. The
-- combat and recovery stats were always replicated and never shown; there is room for them now.
--
-- Two details carried over on purpose:
--   * an attribute row is itself the button: clicking it spends a point. The "+" at its end only
--     shows that it can be clicked.
--   * Level, class and title are placeholders until a progression system feeds them, but they are
--     part of the layout, so they show level 1 and "None" rather than being left out.
--
-- The panel is turned toward the character, so its right side renders larger and lower than its
-- left: a value far to the right of its label looks like it belongs to the next row. Rows are kept
-- short (STAT_WIDTH, fixed attribute columns) so label and value stay together.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local Header = require(script.Parent.Parent.Parent.components.Header)
local PanelShell = require(script.Parent.Parent.Parent.components.PanelShell)
local StatList = require(script.Parent.Parent.Parent.components.StatList)
local VitalsBlock = require(script.Parent.Parent.Parent.components.VitalsBlock)
local ThemeContext = require(script.Parent.Parent.Parent.hooks.ThemeContext)
local useSpring = require(script.Parent.Parent.Parent.hooks.useSpring)
local UISound = require(script.Parent.Parent.Parent.UISound)

local Selector = require(script.Parent.Parent.Parent.selectors.systemStatus)

local e = React.createElement

export type Props = {
	view: Selector.SystemView,
	onSpend: (attributeId: string) -> (),
}

-- Logical pixels.
local TITLE_HEIGHT = 34
local LEFT_WIDTH = 330
local COLUMN_GAP = 28
local BLOCK_GAP = 14
local IDENTITY_HEIGHT = 76
local STAT_ROW_HEIGHT = 22
local STAT_WIDTH = 250
-- Exactly the attribute row's columns, so POINTS sits over the "+" buttons.
local ATTRIBUTE_WIDTH = 6 + 18 + 40 + 100 + 64 + 20 + 4 * 10 + 4
local ATTRIBUTE_ROW_HEIGHT = 30
local SECTION_HEADING_HEIGHT = 22

local function Column(props: { width: number?, layoutOrder: number, children: any })
	local children: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, BLOCK_GAP),
		}),
	}
	if not props.width then
		children.Flex = e("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill })
	end
	for key, child in pairs(props.children) do
		children[key] = child
	end
	return e("Frame", {
		Size = UDim2.new(0, props.width or 0, 1, 0),
		LayoutOrder = props.layoutOrder,
		BackgroundTransparency = 1,
	}, children)
end

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

-- Level large at the left; class and title as caption/value pairs beside it, past a hairline.
local function Identity(props: { identity: Selector.IdentityView, layoutOrder: number })
	local theme = ThemeContext.useTheme()
	local identity = props.identity

	local function pair(caption: string, value: string, y: number)
		return e("Frame", {
			Size = UDim2.new(1, 0, 0, 26),
			Position = UDim2.fromOffset(0, y),
			BackgroundTransparency = 1,
		}, {
			Caption = e(Caption, { text = caption, size = UDim2.new(0, 56, 1, 0) }),
			Value = e("TextLabel", {
				Text = value,
				Size = UDim2.new(1, -56, 1, 0),
				Position = UDim2.fromOffset(56, 0),
				BackgroundTransparency = 1,
				FontFace = theme.face.bodyBold,
				TextSize = theme.type.body,
				TextColor3 = theme.color.textPrimary,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
		})
	end

	return e("Frame", {
		Size = UDim2.new(1, 0, 0, IDENTITY_HEIGHT),
		LayoutOrder = props.layoutOrder,
		BackgroundTransparency = 1,
	}, {
		LevelCaption = e(Caption, {
			text = "LEVEL",
			size = UDim2.fromOffset(110, 16),
			position = UDim2.fromOffset(0, 6),
		}),
		LevelValue = e("TextLabel", {
			Text = tostring(identity.level or 1),
			Size = UDim2.fromOffset(110, 48),
			Position = UDim2.fromOffset(0, 24),
			BackgroundTransparency = 1,
			FontFace = theme.face.display,
			TextSize = 40,
			TextColor3 = theme.color.textHeading,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Divider = e("Frame", {
			Size = UDim2.new(0, 1, 1, -12),
			Position = UDim2.fromOffset(118, 6),
			BackgroundColor3 = theme.color.stroke,
			BackgroundTransparency = theme.chrome.edgeTransparency,
			BorderSizePixel = 0,
		}),
		Pairs = e("Frame", {
			Size = UDim2.new(1, -136, 1, 0),
			Position = UDim2.fromOffset(136, 0),
			BackgroundTransparency = 1,
		}, {
			Class = pair("CLASS", identity.class or "None", 10),
			Title = pair("TITLE", identity.title or "None", 40),
		}),
	})
end

-- One attribute. The whole row is the button; it lights on hover while there are points to spend.
local function AttributeRow(props: {
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
		value ..= ` <font color="#{theme.color.success:ToHex()}" size="{theme.type.label}">+{row.bonus}</font>`
	end

	return e("TextButton", {
		Text = "",
		Size = UDim2.new(1, 0, 0, ATTRIBUTE_ROW_HEIGHT),
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
		Padding = e("UIPadding", {
			PaddingLeft = UDim.new(0, 6),
			PaddingRight = UDim.new(0, 4),
		}),
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 10),
		}),
		Icon = e("ImageLabel", {
			Image = row.icon,
			Size = UDim2.fromOffset(18, 18),
			LayoutOrder = 1,
			BackgroundTransparency = 1,
			ImageColor3 = theme.color.textPrimary,
			ScaleType = Enum.ScaleType.Fit,
		}),
		Short = e("TextLabel", {
			Text = row.short,
			Size = UDim2.new(0, 40, 1, 0),
			LayoutOrder = 2,
			BackgroundTransparency = 1,
			FontFace = theme.face.display,
			TextSize = theme.type.small,
			TextColor3 = theme.color.textHeading,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Name = e("TextLabel", {
			Text = row.label,
			Size = UDim2.new(0, 100, 1, 0),
			LayoutOrder = 3,
			BackgroundTransparency = 1,
			FontFace = theme.face.body,
			TextSize = theme.type.body,
			TextColor3 = theme.color.textMuted,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Value = e("TextLabel", {
			Text = value,
			RichText = true,
			Size = UDim2.new(0, 64, 1, 0),
			LayoutOrder = 4,
			BackgroundTransparency = 1,
			FontFace = theme.face.mono,
			TextSize = theme.type.body,
			TextColor3 = theme.color.textPrimary,
			TextXAlignment = Enum.TextXAlignment.Right,
		}),
		-- Square, like a slot: a hairline box with the plus inside, lit while spending is possible.
		Plus = e("TextLabel", {
			Text = "+",
			Size = UDim2.fromOffset(20, 20),
			LayoutOrder = 5,
			BackgroundTransparency = 1,
			FontFace = theme.face.mono,
			TextSize = theme.type.body,
			TextColor3 = if props.enabled then theme.color.accent else theme.color.textDisabled,
		}, {
			Stroke = e("UIStroke", {
				Color = if props.enabled then theme.color.accent else theme.color.textDisabled,
				Thickness = 1,
				Transparency = glow:map(function(v: number)
					return if props.enabled then 0.5 - 0.5 * v else 0.6
				end),
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}),
		}),
	})
end

local function AttributesSection(props: {
	view: Selector.SystemView,
	layoutOrder: number,
	onSpend: (attributeId: string) -> (),
})
	local theme = ThemeContext.useTheme()
	local view = props.view
	local points = view.availableAP

	local rows: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 2),
		}),
		Heading = e("Frame", {
			Size = UDim2.new(1, 0, 0, SECTION_HEADING_HEIGHT),
			LayoutOrder = 0,
			BackgroundTransparency = 1,
		}, {
			Title = e(Caption, { text = "ATTRIBUTES", size = UDim2.fromScale(0.5, 1) }),
			-- Accent while there is something to spend, so the reason to open this view stands out.
			Points = e("TextLabel", {
				Text = `<font face="Michroma" size="{theme.type.label}" color="#{theme.color.textMuted:ToHex()}">POINTS  </font>{points}`,
				RichText = true,
				Size = UDim2.fromScale(0.5, 1),
				Position = UDim2.fromScale(0.5, 0),
				BackgroundTransparency = 1,
				FontFace = theme.face.mono,
				TextSize = theme.type.body,
				TextColor3 = if points > 0 then theme.color.accent else theme.color.textMuted,
				TextXAlignment = Enum.TextXAlignment.Right,
			}),
		}),
	}
	for index, row in ipairs(view.attributes) do
		rows[row.id] = e(AttributeRow, {
			row = row,
			layoutOrder = index,
			enabled = points > 0,
			onSpend = props.onSpend,
		})
	end

	return e("Frame", {
		Size = UDim2.fromOffset(ATTRIBUTE_WIDTH, SECTION_HEADING_HEIGHT + #view.attributes * (ATTRIBUTE_ROW_HEIGHT + 2)),
		LayoutOrder = props.layoutOrder,
		BackgroundTransparency = 1,
	}, rows)
end

local function StatSection(props: { title: string, stats: { Selector.StatRow }, layoutOrder: number })
	if #props.stats == 0 then
		return nil
	end
	local rows: { [string]: any } = {}
	for index, stat in ipairs(props.stats) do
		rows[`Stat{index}`] = e(StatList.Row, {
			label = stat.label,
			value = stat.value,
			role = "BodyText",
			layoutOrder = index,
			rowHeight = STAT_ROW_HEIGHT,
			labelWidth = 0.66,
		})
	end
	return e("Frame", {
		Size = UDim2.fromOffset(STAT_WIDTH, StatList.height(#props.stats, STAT_ROW_HEIGHT)),
		LayoutOrder = props.layoutOrder,
		BackgroundTransparency = 1,
	}, {
		Section = e(StatList.Section, {
			title = props.title,
			rowHeight = STAT_ROW_HEIGHT,
			children = rows,
		}),
	})
end

local function StatusView(props: Props)
	local theme = ThemeContext.useTheme()
	local view = props.view

	return e(PanelShell, { padding = 20, gap = 10 }, {
		Title = e("Frame", {
			Size = UDim2.new(1, 0, 0, TITLE_HEIGHT),
			LayoutOrder = 1,
			BackgroundTransparency = 1,
		}, {
			Header = e(Header, { title = "STATUS", height = 1 }),
		}),

		Columns = e("Frame", {
			Size = UDim2.fromScale(1, 0),
			LayoutOrder = 2,
			BackgroundTransparency = 1,
		}, {
			Flex = e("UIFlexItem", { FlexMode = Enum.UIFlexMode.Fill }),
			Layout = e("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, COLUMN_GAP / 2),
			}),
			Left = e(Column, { width = LEFT_WIDTH, layoutOrder = 1 }, {
				Identity = e(Identity, { identity = view.identity, layoutOrder = 1 }),
				Vitals = e(VitalsBlock.render, {
					vitals = view.vitals,
					size = UDim2.new(1, 0, 0, VitalsBlock.HEIGHT),
					layoutOrder = 2,
				}),
				Combat = e(StatSection, { title = "Combat", stats = view.combatStats, layoutOrder = 3 }),
			}),
			Divider = e("Frame", {
				Size = UDim2.new(0, 1, 1, 0),
				LayoutOrder = 2,
				BackgroundColor3 = theme.color.stroke,
				BackgroundTransparency = theme.chrome.edgeTransparency,
				BorderSizePixel = 0,
			}),
			Right = e(Column, { layoutOrder = 3 }, {
				Attributes = e(AttributesSection, { view = view, layoutOrder = 1, onSpend = props.onSpend }),
				Recovery = e(StatSection, { title = "Recovery", stats = view.recoveryStats, layoutOrder = 2 }),
			}),
		}),
	})
end

return StatusView
