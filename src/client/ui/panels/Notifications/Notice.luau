--!strict
-- One System notice: a tag line in the notice's tone over its subject -- an item as its glyph and
-- name in the rarity colour with a count, or plain text.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local Glyph = require(script.Parent.Parent.Parent.components.Glyph)
local PanelFrame = require(script.Parent.Parent.Parent.components.PanelFrame)
local ThemeContext = require(script.Parent.Parent.Parent.hooks.ThemeContext)
local NotificationClient = require(script.Parent.Parent.Parent.controllers.NotificationClient)

local e = React.createElement

export type Props = {
	notice: NotificationClient.Notice,
}

local Notice = {}

-- Pixels.
Notice.SIZE = Vector2.new(320, 58)

local function toneColor(theme: any, tone: NotificationClient.Tone): Color3
	if tone == "error" then
		return theme.color.danger
	elseif tone == "success" then
		return theme.color.success
	elseif tone == "warning" then
		return theme.rarity.rare
	end
	return theme.color.accent
end

function Notice.render(props: Props)
	local theme = ThemeContext.useTheme()
	local notice = props.notice
	local tone = toneColor(theme, notice.tone)
	local tint = if notice.rarity then (theme.rarity :: any)[notice.rarity] else nil

	local subject: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		}),
		Text = e("TextLabel", {
			Text = notice.text or "",
			Size = UDim2.fromScale(0, 1),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = 2,
			BackgroundTransparency = 1,
			FontFace = if tint then theme.face.bodyBold else theme.face.body,
			TextSize = theme.type.body,
			TextColor3 = tint or theme.color.textPrimary,
		}),
	}
	if notice.glyph then
		subject.GlyphCell = e("Frame", {
			Size = UDim2.fromOffset(18, 18),
			LayoutOrder = 1,
			BackgroundTransparency = 1,
		}, {
			Glyph = e(Glyph, { glyph = notice.glyph, color = tint or theme.color.textPrimary, thickness = 1.25 }),
		})
	end
	if notice.count > 1 then
		subject.Count = e("TextLabel", {
			Text = `x{notice.count}`,
			Size = UDim2.fromScale(0, 1),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = 3,
			BackgroundTransparency = 1,
			FontFace = theme.face.mono,
			TextSize = theme.type.small,
			TextColor3 = theme.color.textMuted,
		})
	end

	return e(PanelFrame, {
		layout = "stack",
		padding = 9,
		gap = 2,
		brackets = "small",
		fillTransparency = theme.styles.AmbientPanel.BackgroundTransparency,
	}, {
		Tag = e("Frame", {
			Size = UDim2.new(1, 0, 0, 14),
			LayoutOrder = 1,
			BackgroundTransparency = 1,
		}, {
			Marker = e("Frame", {
				Size = UDim2.fromOffset(6, 6),
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 2, 0.5, 0),
				Rotation = 45,
				BackgroundColor3 = tone,
				BorderSizePixel = 0,
			}),
			Label = e("TextLabel", {
				Text = notice.tag,
				Size = UDim2.new(1, -16, 1, 0),
				Position = UDim2.fromOffset(16, 0),
				BackgroundTransparency = 1,
				FontFace = theme.face.display,
				TextSize = theme.type.label,
				TextColor3 = tone,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
		}),
		Subject = e("Frame", {
			Size = UDim2.new(1, 0, 0, 24),
			LayoutOrder = 2,
			BackgroundTransparency = 1,
		}, subject),
	})
end

return Notice
