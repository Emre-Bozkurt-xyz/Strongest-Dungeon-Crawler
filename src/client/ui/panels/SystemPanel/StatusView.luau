--!strict
-- The character status sheet: title, identity, vitals, attributes.
--
-- Ported from docs/ui/SystemPanel.rbxmx with docs/ui/SystemPanelOTS.png as the reference for the
-- rendered result. The original is a *composed* layout -- an inset card carrying four absolutely
-- positioned blocks -- not a vertical stack, so this uses PanelShell in "free" mode and places each
-- block by scale where the Studio panel put it.
--
-- Three details that look arbitrary but are not:
--   * an attribute row is itself the button. There are no separate "+" controls; clicking a row
--     spends a point into it.
--   * the vitals band is horizontal: HP bar, MP bar, then the stamina ring at the right end.
--   * Level/Class/Title are placeholders. Nothing feeds them yet, but they are part of the layout
--     and omitting them leaves a hole where the identity block belongs.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local Panel = require(script.Parent.Parent.Parent.components.Panel)
local PanelShell = require(script.Parent.Parent.Parent.components.PanelShell)
local Text = require(script.Parent.Parent.Parent.components.Text)
local VitalGauge = require(script.Parent.Parent.Parent.components.VitalGauge)
local RadialGauge = require(script.Parent.Parent.Parent.components.RadialGauge)

local ThemeContext = require(script.Parent.Parent.Parent.hooks.ThemeContext)

local Selector = require(script.Parent.Parent.Parent.selectors.systemStatus)

local e = React.createElement

export type Props = {
	view: Selector.SystemView,
	onSpend: (attributeId: string) -> (),
}

local HEART_ICON = "rbxassetid://100398419080154"
local DROPLET_ICON = "rbxassetid://109364647302001"

local function findVital(view: Selector.SystemView, label: string): Selector.VitalView?
	for _, vital in ipairs(view.vitals) do
		if vital.label == label then
			return vital
		end
	end
	return nil
end

-- One attribute cell. The whole cell is the button; clicking it spends a point.
local function AttributeRow(props: {
	row: Selector.AttributeRow,
	layoutOrder: number,
	enabled: boolean,
	onSpend: (attributeId: string) -> (),
})
	local theme = ThemeContext.useTheme()
	local row = props.row

	local values: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Name = e("TextLabel", {
			LayoutOrder = 1,
			Text = `{row.short}:`,
			Size = UDim2.fromScale(0, 1),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Font = theme.font.body,
			TextColor3 = theme.color.textHeading,
			TextScaled = true,
		}),
		Base = e("TextLabel", {
			LayoutOrder = 2,
			Text = tostring(row.base),
			Size = UDim2.fromScale(0, 1),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Font = theme.font.body,
			TextColor3 = theme.color.textHeading,
			TextScaled = true,
		}),
	}
	if row.bonus ~= 0 then
		values.Bonus = e("TextLabel", {
			LayoutOrder = 3,
			Text = `(+{row.bonus})`,
			Size = UDim2.fromScale(0, 0.8),
			AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1,
			Font = theme.font.body,
			TextColor3 = theme.color.success,
			TextScaled = true,
		}, {
			Padding = e("UIPadding", { PaddingLeft = UDim.new(0, 5) }),
		})
	end

	return e("TextButton", {
		Text = "",
		LayoutOrder = props.layoutOrder,
		BackgroundTransparency = 1,
		Active = props.enabled,
		[React.Event.Activated] = function()
			if props.enabled then
				props.onSpend(row.id)
			end
		end,
	}, {
		Icon = e("ImageLabel", {
			Image = row.icon,
			Size = UDim2.fromScale(0.18, 0.5),
			Position = UDim2.fromScale(0.02, 0.5),
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundTransparency = 1,
			ImageColor3 = theme.color.textHeading,
			ScaleType = Enum.ScaleType.Fit,
		}),
		Values = e("Frame", {
			Size = UDim2.fromScale(0.74, 0.5),
			Position = UDim2.fromScale(0.24, 0.5),
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundTransparency = 1,
		}, values),
	})
end

local function StatusView(props: Props)
	local theme = ThemeContext.useTheme()
	local view = props.view
	local identity = view.identity

	local health = findVital(view, "HP")
	local mana = findVital(view, "MP")
	local stamina = findVital(view, "Stamina")

	local cells: { [string]: any } = {
		Layout = e("UIGridLayout", {
			CellSize = UDim2.fromScale(0.5, 0.3333),
			CellPadding = UDim2.fromScale(0, 0),
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
		Padding = e("UIPadding", {
			PaddingTop = UDim.new(0.05, 0),
			PaddingBottom = UDim.new(0.05, 0),
			PaddingLeft = UDim.new(0.05, 0),
			PaddingRight = UDim.new(0.05, 0),
		}),
	}
	for index, row in ipairs(view.attributes) do
		cells[row.id] = e(AttributeRow, {
			row = row,
			layoutOrder = index - 1,
			enabled = view.availableAP > 0,
			onSpend = props.onSpend,
		})
	end
	-- Sixth grid cell, sharing the 2x3 grid with the five attributes.
	cells.AvailablePoints = e("Frame", {
		LayoutOrder = 5,
		BackgroundTransparency = 1,
	}, {
		Caption = e(Text, {
			text = "Available\nAttribute\nPoints",
			role = "MutedText",
			size = UDim2.fromScale(0.42, 0.7),
			position = UDim2.fromScale(0.04, 0.5),
			anchorPoint = Vector2.new(0, 0.5),
			alignX = Enum.TextXAlignment.Right,
		}),
		Value = e("TextLabel", {
			Text = tostring(view.availableAP),
			Size = UDim2.fromScale(0.46, 0.55),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundTransparency = 1,
			Font = theme.font.body,
			TextColor3 = theme.color.textHeading,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
	})

	return e(PanelShell, {
		inset = UDim2.fromScale(0.62, 0.82),
		layout = "free",
		transparency = 0.55,
		padding = theme.metrics.paddingMd,
	}, {
		Title = e(Panel, {
			stroke = true,
			size = UDim2.fromScale(0.35, 0.1),
			position = UDim2.fromScale(0.5, 0.01),
			anchorPoint = Vector2.new(0.5, 0),
			props = { BackgroundTransparency = 1 },
		}, {
			Label = e(Text, {
				text = "STATUS",
				role = "PanelHeading",
				size = UDim2.fromScale(1, 1),
				alignX = Enum.TextXAlignment.Center,
				glow = true,
			}),
		}),

		-- Level large at the left, Class and Title stacked to its right.
		Info = e("Frame", {
			Size = UDim2.fromScale(0.8, 0.17),
			Position = UDim2.fromScale(0.5, 0.14),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundTransparency = 1,
		}, {
			LevelValue = e(Text, {
				text = if identity.level then tostring(identity.level) else "999",
				role = "PanelHeading",
				size = UDim2.fromScale(0.22, 0.62),
				position = UDim2.fromScale(0.06, 0),
				alignX = Enum.TextXAlignment.Center,
				alignY = Enum.TextYAlignment.Bottom,
				glow = true,
			}),
			LevelCaption = e(Text, {
				text = "LEVEL",
				role = "MutedText",
				size = UDim2.fromScale(0.22, 0.3),
				position = UDim2.fromScale(0.06, 0.64),
				alignX = Enum.TextXAlignment.Center,
			}),
			ClassCaption = e(Text, {
				text = "Class",
				role = "MutedText",
				size = UDim2.fromScale(0.14, 0.4),
				position = UDim2.fromScale(0.32, 0.06),
				alignX = Enum.TextXAlignment.Right,
			}),
			ClassValue = e(Text, {
				text = identity.class or "None",
				role = "PanelHeading",
				size = UDim2.fromScale(0.46, 0.42),
				position = UDim2.fromScale(0.5, 0.04),
				alignX = Enum.TextXAlignment.Left,
				glow = true,
			}),
			TitleCaption = e(Text, {
				text = "Title",
				role = "MutedText",
				size = UDim2.fromScale(0.14, 0.4),
				position = UDim2.fromScale(0.32, 0.54),
				alignX = Enum.TextXAlignment.Right,
			}),
			TitleValue = e(Text, {
				text = identity.title or "None",
				role = "PanelHeading",
				size = UDim2.fromScale(0.46, 0.42),
				position = UDim2.fromScale(0.5, 0.52),
				alignX = Enum.TextXAlignment.Left,
				glow = true,
			}),
		}),

		Vitals = e(Panel, {
			stroke = true,
			size = UDim2.fromScale(0.94, 0.16),
			position = UDim2.fromScale(0.5, 0.35),
			anchorPoint = Vector2.new(0.5, 0),
			props = { BackgroundTransparency = 1 },
		}, {
			Padding = e("UIPadding", {
				PaddingLeft = UDim.new(0.03, 0),
				PaddingRight = UDim.new(0.02, 0),
			}),
			Health = if health
				then e(VitalGauge, {
					icon = HEART_ICON,
					caption = "HP",
					vital = health,
					size = UDim2.fromScale(0.37, 0.8),
					position = UDim2.fromScale(0, 0.5),
					anchorPoint = Vector2.new(0, 0.5),
				})
				else nil,
			Mana = if mana
				then e(VitalGauge, {
					icon = DROPLET_ICON,
					caption = "MP",
					vital = mana,
					size = UDim2.fromScale(0.37, 0.8),
					-- Gapped well clear of the HP bar; back to back the two read as one long rule.
					position = UDim2.fromScale(0.46, 0.5),
					anchorPoint = Vector2.new(0, 0.5),
				})
				else nil,
			Stamina = if stamina
				then e(RadialGauge, {
					value = stamina.ratio,
					label = "STAM",
					size = UDim2.fromScale(0.1, 0.9),
					position = UDim2.fromScale(0.87, 0.5),
					anchorPoint = Vector2.new(0, 0.5),
				})
				else nil,
		}),

		Attributes = e(Panel, {
			stroke = true,
			size = UDim2.fromScale(0.94, 0.4),
			position = UDim2.fromScale(0.5, 0.55),
			anchorPoint = Vector2.new(0.5, 0),
			props = { BackgroundTransparency = 1 },
		}, cells),
	})
end

return StatusView
