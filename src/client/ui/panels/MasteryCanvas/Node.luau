--!strict
-- One node of a mastery tree: a small card of light in the System chrome.
--
-- Three looks, one per thing the player can know about it: a fogged node is only its corners and a
-- question mark (it exists, nothing more); a locked node shows its name and what it takes; an
-- unlocked node is lit, the form in use outlined in the focus colour. Only forms are chosen here;
-- other unlocked nodes say what kind of node they are.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local MasteryTree = require(ReplicatedStorage.Shared.progression.MasteryTree)

local ThemeContext = require(script.Parent.Parent.Parent.hooks.ThemeContext)
local useSpring = require(script.Parent.Parent.Parent.hooks.useSpring)
local Brackets = require(script.Parent.Parent.Parent.components.Brackets)
local Glyph = require(script.Parent.Parent.Parent.components.Glyph)
local UISound = require(script.Parent.Parent.Parent.UISound)

local e = React.createElement

local Node = {}

Node.SIZE = Vector2.new(212, 76)

export type Props = {
	node: MasteryTree.Node,
	glyph: string,
	position: Vector2,
	-- 0..1 binding: this node's part of the canvas's entrance.
	appear: any,
	onActivated: () -> (),
}

local KIND_LABEL: { [string]: string } = {
	infusion = "INFUSION",
	passive = "PASSIVE",
	select = "SELECTABLE PASSIVE",
	attuned = "ATTUNED",
}

-- The one line under the name: what the node is to the player right now.
local function statusText(node: MasteryTree.Node): string
	if not node.unlocked then
		return node.requirement or "LOCKED"
	end
	if node.selected then
		return "IN USE"
	end
	if node.kind == "form" then
		if node.shapeId then
			return "AVAILABLE"
		end
		return if node.built then "DOES NOT FIT YOUR WEAPON" else "NOT BUILT YET"
	end
	return KIND_LABEL[node.kind] or "UNLOCKED"
end

local function NodeView(props: Props)
	local theme = ThemeContext.useTheme()
	local hovered, setHovered = React.useState(false)
	local node = props.node
	local fogged = node.visibility == "fogged"
	local hover = useSpring(if hovered and not fogged then 1 else 0, theme.motion.snap)

	local focus = theme.color.accent
	local frameColor = if node.selected then focus else if fogged then theme.color.textDisabled else theme.color.stroke
	local nameColor = if node.unlocked then theme.color.textHeading else theme.color.textMuted
	local status = statusText(node)
	local statusColor = if node.selected
		then focus
		else if node.unlocked then theme.color.textMuted else theme.color.danger

	local function fade(base: number)
		return props.appear:map(function(a: number)
			return 1 - (1 - base) * math.clamp(a, 0, 1)
		end)
	end

	local card: { [string]: any } = {
		Scale = e("UIScale", {
			Scale = hover:map(function(h: number)
				return 1 + 0.035 * h
			end),
		}),
		Frame = e(Brackets, {
			size = "small",
			color = frameColor,
			progress = props.appear,
			edgeTransparency = if fogged then 1 elseif node.selected then 0.35 else 0.75,
		}),
	}

	if fogged then
		card.Unknown = e("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = "?",
			FontFace = theme.face.mono,
			TextSize = theme.type.title,
			TextColor3 = theme.color.textDisabled,
			TextTransparency = fade(0),
		})
	else
		card.Fill = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = theme.color.surface,
			BackgroundTransparency = props.appear:map(function(a: number)
				local base = if node.unlocked then 0.25 else 0.55
				return 1 - (1 - base) * math.clamp(a, 0, 1)
			end),
			BorderSizePixel = 0,
			ZIndex = 1,
		}, {
			Lit = e("UIGradient", {
				Rotation = 90,
				Transparency = NumberSequence.new(0, 0.5),
			}),
		})
		card.Icon = e("Frame", {
			Size = UDim2.fromOffset(40, 40),
			Position = UDim2.new(0, 16, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundTransparency = 1,
			ZIndex = 3,
		}, {
			Glyph = e(Glyph, {
				glyph = props.glyph,
				color = if node.selected then focus elseif node.unlocked then theme.color.textHeading else theme.color.textDisabled,
				thickness = 1.5,
			}),
		})
		card.Name = e("TextLabel", {
			Size = UDim2.new(1, -76, 0, 22),
			Position = UDim2.fromOffset(66, 14),
			BackgroundTransparency = 1,
			Text = string.upper(node.displayName),
			FontFace = theme.face.display,
			TextSize = theme.type.small,
			TextColor3 = nameColor,
			TextTransparency = fade(0),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 3,
		})
		card.Status = e("TextLabel", {
			Size = UDim2.new(1, -76, 0, 18),
			Position = UDim2.fromOffset(66, 42),
			BackgroundTransparency = 1,
			Text = status,
			FontFace = theme.face.bodyBold,
			TextSize = theme.type.label,
			TextColor3 = statusColor,
			TextTransparency = fade(0),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 3,
		})
	end

	return e("TextButton", {
		Size = UDim2.fromOffset(Node.SIZE.X, Node.SIZE.Y),
		Position = UDim2.fromOffset(props.position.X, props.position.Y),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 5,
		[React.Event.MouseEnter] = function()
			setHovered(true)
			if not fogged then
				UISound.play("hover")
			end
		end,
		[React.Event.MouseLeave] = function()
			setHovered(false)
		end,
		[React.Event.Activated] = function()
			if not fogged then
				props.onActivated()
			end
		end,
	}, card)
end

Node.render = NodeView

return Node
