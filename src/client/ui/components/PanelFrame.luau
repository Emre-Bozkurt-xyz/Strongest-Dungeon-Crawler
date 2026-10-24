--!strict
-- A panel's outer chrome: one translucent fill that thins toward the bottom, corner brackets, and a
-- padded body holding the content.
--
-- This is the part a skin restyles most, so everything visual comes from `theme.chrome` and the
-- colour tokens; panels never draw their own frame. Content is kept in its own padded body so the
-- chrome is never under the content's padding (see Brackets).
--
-- `layout = "stack"` stacks the body's children vertically by LayoutOrder; "free" leaves them to
-- position themselves.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ThemeContext = require(script.Parent.Parent.hooks.ThemeContext)
local Brackets = require(script.Parent.Brackets)

local e = React.createElement

export type Props = {
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layout: ("stack" | "free")?,
	gap: number?,
	padding: number?,
	-- Overrides the theme's fill transparency, e.g. for an always-on surface that needs more body.
	fillTransparency: number?,
	-- 0..1 binding driving the materialise: corners fly out, the fill comes up. Omit to show static.
	progress: any?,
	children: any?,
}

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function PanelFrame(props: Props)
	local theme = ThemeContext.useTheme()
	local chrome = theme.chrome
	local fill = props.fillTransparency or chrome.fillTransparency
	local pad = UDim.new(0, props.padding or theme.metrics.paddingLg)

	local body: { [string]: any } = {
		Padding = e("UIPadding", {
			PaddingTop = pad,
			PaddingBottom = pad,
			PaddingLeft = pad,
			PaddingRight = pad,
		}),
	}
	if (props.layout or "stack") == "stack" then
		body.Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, props.gap or theme.metrics.paddingSm),
		})
	end
	if props.children then
		for key, child in pairs(props.children) do
			body[key] = child
		end
	end

	return e("Frame", {
		Size = props.size or UDim2.fromScale(1, 1),
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		BackgroundColor3 = theme.color.surface,
		BackgroundTransparency = if props.progress
			then props.progress:map(function(p: number)
				return lerp(1, fill, math.clamp(p, 0, 1))
			end)
			else fill,
		BorderSizePixel = 0,
	}, {
		-- Denser at the top where the header sits, thinning downward, so the panel reads as projected
		-- light over the world rather than a slab.
		Fade = e("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(1, chrome.fillFade),
			}),
		}),
		Brackets = e(Brackets, { size = "panel", progress = props.progress }),
		Body = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
		}, body),
	})
end

return PanelFrame
