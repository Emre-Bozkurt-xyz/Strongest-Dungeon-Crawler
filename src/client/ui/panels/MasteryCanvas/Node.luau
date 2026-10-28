--!strict
-- One node of the constellation (docs/planning/mastery-mind-space.md, "Visual language").
--
-- Monochrome: white for what is yours, grey for what is not yet. A passive is a bare circle. A
-- selectable passive is larger, embroidered and carries an icon; an attunement-only node's embroidery
-- is a closed ring. A form or infusion is the most important: the heaviest embroidery, an icon, and
-- the System's bracket corners, grey while available and white while in use. A fogged node is only a
-- faint star. An earned node of a track that is not attuned is dormant: earned, but drawn mid-grey.
--
-- A node unlocked since the player last looked pulses until they hover it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local MasteryTree = require(ReplicatedStorage.Shared.progression.MasteryTree)
local MasteryArt = require(ReplicatedStorage.Shared.progression.MasteryArt)

local ThemeContext = require(script.Parent.Parent.Parent.hooks.ThemeContext)
local useSpring = require(script.Parent.Parent.Parent.hooks.useSpring)
local Brackets = require(script.Parent.Parent.Parent.components.Brackets)
local UISound = require(script.Parent.Parent.Parent.UISound)

local e = React.createElement

local Node = {}

local INK = Color3.fromRGB(238, 241, 246)
local MID = Color3.fromRGB(138, 144, 155)
local GREY = Color3.fromRGB(93, 99, 111)
local VOID = Color3.fromRGB(4, 5, 8)

-- Body radius by kind, in pixels.
Node.RADIUS = { passive = 11, select = 25, attuned = 25, form = 34, infusion = 34 } :: { [string]: number }

-- Embroidery per kind: the frame art, and how far past the body its outer edge reaches.
local FRAMES: { [string]: { key: string, reach: number } } = {
	select = { key = "frame.select", reach = 16 },
	attuned = { key = "frame.attuned_node", reach = 15 },
	form = { key = "frame.form", reach = 22 },
	infusion = { key = "frame.form", reach = 22 },
}

-- How far past the body a form's bracket corners sit.
local BRACKET_REACH = 36

-- How far a node's drawing reaches from its centre: where a tooltip beside it starts.
function Node.reachOf(kind: string): number
	local r = Node.RADIUS[kind] or Node.RADIUS.passive
	if kind == "form" or kind == "infusion" then
		return r + BRACKET_REACH
	end
	local frame = FRAMES[kind]
	return r + (if frame then frame.reach else 4)
end

-- One pulse: a ring swelling out from the node and fading.
local PULSE_PERIOD = 1.6
local PULSE_TRAVEL = 28

export type Props = {
	node: MasteryTree.Node,
	-- The track's emblem, for nodes whose own art is not made yet.
	trackId: string,
	-- Content-space centre.
	position: Vector2,
	unseen: boolean,
	-- 0..1 binding: this node's part of the entrance.
	appear: any,
	-- Seconds binding, shared by every pulse so they beat together.
	clock: any,
	onHover: () -> (),
	onLeave: () -> (),
	onActivated: () -> (),
}

local function join(base: { [string]: any }, extra: { [string]: any }): { [string]: any }
	local out = table.clone(base)
	for key, value in pairs(extra) do
		out[key] = value
	end
	return out
end

local function circle(diameter: number, props: { [string]: any }, children: { [string]: any }?)
	local merged = join({
		Size = UDim2.fromOffset(diameter, diameter),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BorderSizePixel = 0,
	}, props)
	local inner: { [string]: any } = { Round = e("UICorner", { CornerRadius = UDim.new(1, 0) }) }
	for key, value in pairs(children or {}) do
		inner[key] = value
	end
	return e("Frame", merged, inner)
end

local function FoggedNode(props: Props)
	return e("Frame", {
		Size = UDim2.fromOffset(14, 14),
		Position = UDim2.fromOffset(props.position.X, props.position.Y),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 5,
		Visible = props.appear:map(function(a: number)
			return a > 0.02
		end),
	}, {
		Dot = circle(3, { BackgroundColor3 = INK, BackgroundTransparency = 0.45 }),
		Across = e("Frame", {
			Size = UDim2.fromOffset(12, 1),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = INK,
			BackgroundTransparency = 0.7,
			BorderSizePixel = 0,
		}),
		Down = e("Frame", {
			Size = UDim2.fromOffset(1, 12),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = INK,
			BackgroundTransparency = 0.7,
			BorderSizePixel = 0,
		}),
	})
end

local function NodeView(props: Props)
	local theme = ThemeContext.useTheme()
	local hovered, setHovered = React.useState(false)
	local hover = useSpring(if hovered then 1 else 0, theme.motion.snap)
	local node = props.node
	local kind = node.kind
	local r = Node.RADIUS[kind] or Node.RADIUS.passive
	local lit = node.unlocked and not node.dormant
	local on = node.selected
	local ring = if kind == "passive"
		then (if lit then INK elseif node.unlocked then MID else GREY)
		else (if on then INK elseif lit then MID else GREY)
	local iconInk = if on then INK elseif lit then MID else GREY
	local frame = FRAMES[kind]
	local hit = (r + (if frame then frame.reach else 6)) * 2 + 8

	local children: { [string]: any } = {
		Scale = e("UIScale", {
			Scale = React.joinBindings({ appear = props.appear, hover = hover }):map(
				function(values: { appear: number, hover: number })
					return (0.6 + 0.4 * math.clamp(values.appear, 0, 1)) * (1 + 0.08 * values.hover)
				end
			),
		}),
	}

	if frame then
		local art = MasteryArt.get(frame.key)
		local diameter = (r + frame.reach) * 2
		children.Embroidery = if art
			then e(
				"ImageLabel",
				join(MasteryArt.imageProps(art), {
					Size = UDim2.fromOffset(diameter, diameter),
					Position = UDim2.fromScale(0.5, 0.5),
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundTransparency = 1,
					ImageColor3 = ring,
					ScaleType = Enum.ScaleType.Fit,
					ZIndex = 1,
				})
			)
			else circle(diameter - 8, { BackgroundTransparency = 1, ZIndex = 1 }, {
				Stroke = e("UIStroke", { Color = ring, Thickness = 1, Transparency = 0.2 }),
			})
	end

	if (kind == "form" or kind == "infusion") and node.unlocked then
		local size = (r + BRACKET_REACH) * 2
		children.Corners = e("Frame", {
			Size = UDim2.fromOffset(size, size),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			ZIndex = 1,
		}, {
			Brackets = e(Brackets, { size = "small", color = if on then INK else GREY, edgeTransparency = 1 }),
		})
	end

	children.Body = circle(r * 2, { BackgroundColor3 = VOID, ZIndex = 2 }, {
		Stroke = e("UIStroke", {
			Color = ring,
			Thickness = if kind == "passive" then 1.4 else 1.2,
			-- Dormant: earned but not in effect, so the outline is there but faint.
			Transparency = if node.unlocked and node.dormant then 0.45 else 0,
		}),
		Inner = if on and kind ~= "passive"
			then circle(r * 2 - 7, { BackgroundTransparency = 1 }, {
				Stroke = e("UIStroke", { Color = INK, Thickness = 1, Transparency = 0.55 }),
			})
			else nil,
	})

	if kind ~= "passive" then
		local art = MasteryArt.get(node.id) or MasteryArt.get(`mastery.{props.trackId}`)
		if art then
			children.Icon = e(
				"ImageLabel",
				join(MasteryArt.imageProps(art), {
					Size = UDim2.fromOffset(r * 1.3, r * 1.3),
					Position = UDim2.fromScale(0.5, 0.5),
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundTransparency = 1,
					ImageColor3 = iconInk,
					ScaleType = Enum.ScaleType.Fit,
					ZIndex = 3,
				})
			)
		end
		local below = if kind == "form" or kind == "infusion" then BRACKET_REACH + 8 else (frame and frame.reach or 6) + 8
		children.Name = e("TextLabel", {
			Size = UDim2.fromOffset(240, 16),
			Position = UDim2.new(0.5, 0, 0.5, r + below),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundTransparency = 1,
			Text = string.upper(node.displayName),
			FontFace = theme.face.display,
			TextSize = 13,
			TextColor3 = if lit then (if on then INK else MID) else GREY,
			ZIndex = 3,
		})
	end

	if props.unseen then
		children.Pulse = circle(r * 2, {
			BackgroundTransparency = 1,
			Size = props.clock:map(function(t: number)
				local phase = (t % PULSE_PERIOD) / PULSE_PERIOD
				local diameter = (r + 6 + phase * PULSE_TRAVEL) * 2
				return UDim2.fromOffset(diameter, diameter)
			end),
			ZIndex = 0,
		}, {
			Stroke = e("UIStroke", {
				Color = INK,
				Thickness = 1,
				Transparency = props.clock:map(function(t: number)
					local phase = (t % PULSE_PERIOD) / PULSE_PERIOD
					return 1 - (1 - phase) * 0.6
				end),
			}),
		})
	end

	return e("TextButton", {
		Size = UDim2.fromOffset(hit, hit),
		Position = UDim2.fromOffset(props.position.X, props.position.Y),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 5,
		Visible = props.appear:map(function(a: number)
			return a > 0.02
		end),
		[React.Event.MouseEnter] = function()
			setHovered(true)
			UISound.play("hover")
			props.onHover()
		end,
		[React.Event.MouseLeave] = function()
			setHovered(false)
			props.onLeave()
		end,
		[React.Event.Activated] = props.onActivated,
	}, children)
end

function Node.render(props: Props)
	if props.node.visibility == "fogged" then
		return e(FoggedNode, props)
	end
	return e(NodeView, props)
end

return Node
