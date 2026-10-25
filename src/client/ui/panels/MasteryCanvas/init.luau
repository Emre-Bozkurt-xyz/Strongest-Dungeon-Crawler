--!strict
-- The mastery canvas: one mastery's tree, laid out left to right on an open field the player drags
-- around (docs/planning/progression-direction.md, "Mastery pages").
--
-- An airy void rather than a scrolling panel: the tree sits in space with a faint grid to show it
-- moving, and the view is bounded so it can drift past the tree's edge but never lose it. Fog is the
-- tree model's (MasteryTree): only one or two nodes past what the player has reached are drawn.
--
-- Entrance, as one 0..1 progress: the world dims, a line of light draws across the screen and
-- fades, the header comes up, and the tree assembles column by column from its root. Closing runs it
-- backward, faster.
--
-- `script` here IS the MasteryCanvas module (init.luau collapses into its folder), so Parent is
-- `panels` and Parent.Parent is `ui`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local React = require(ReplicatedStorage.Packages.React)
local MasteryTracks = require(ReplicatedStorage.Shared.progression.MasteryTracks)
local MasteryTree = require(ReplicatedStorage.Shared.progression.MasteryTree)
local Ease = require(ReplicatedStorage.Shared.ui.Ease)

local ThemeContext = require(script.Parent.Parent.hooks.ThemeContext)
local useSpring = require(script.Parent.Parent.hooks.useSpring)
local Brackets = require(script.Parent.Parent.components.Brackets)
local Button = require(script.Parent.Parent.components.Button)
local Glyph = require(script.Parent.Parent.components.Glyph)
local UISound = require(script.Parent.Parent.UISound)
local MasteryCanvasController = require(script.Parent.Parent.controllers.MasteryCanvasController)
local ProgressionClient = require(script.Parent.Parent.Parent.Progression.ProgressionClient)
local Node = require(script.Node)
local Edge = require(script.Edge)

local e = React.createElement

-- Pixels between nodes, across columns and down rows.
local GAP = Vector2.new(96, 36)
-- How far past the tree's edge the view's centre may travel.
local MARGIN = 320
-- Spacing of the faint grid that shows the field moving.
local GRID_STEP = 120

local OPEN_TIME = 0.55
local CLOSE_TIME = 0.18

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- 0..1 of the entrance between `from` and `to`, braking hard into place.
local function stage(t: number, from: number, to: number): number
	return Ease.expoOut(Ease.clamp01((t - from) / (to - from)))
end

-- When a node's column assembles in the entrance. Capped so a deep tree still finishes in time.
local function columnStage(t: number, column: number): number
	local start = 0.38 + 0.08 * math.min(column, 4)
	return stage(t, start, start + 0.24)
end

local function nodePosition(node: MasteryTree.Node): Vector2
	return Vector2.new(node.column * (Node.SIZE.X + GAP.X), node.row * (Node.SIZE.Y + GAP.Y))
end

local function treeBounds(tree: MasteryTree.Tree?): (Vector2, Vector2)
	if not tree or #tree.nodes == 0 then
		return Vector2.zero, Node.SIZE
	end
	local minimum, maximum = Vector2.new(math.huge, math.huge), Vector2.new(-math.huge, -math.huge)
	for _, node in ipairs(tree.nodes) do
		local position = nodePosition(node)
		minimum = minimum:Min(position)
		maximum = maximum:Max(position + Node.SIZE)
	end
	return minimum, maximum
end

local function viewSize(): Vector2
	local camera = Workspace.CurrentCamera
	return if camera then camera.ViewportSize else Vector2.new(1920, 1080)
end

-- Keep the view's centre within the tree's bounds plus the margin.
local function clampPan(pan: Vector2, minimum: Vector2, maximum: Vector2): Vector2
	local centre = viewSize() / 2
	return Vector2.new(
		math.clamp(pan.X, centre.X - (maximum.X + MARGIN), centre.X - (minimum.X - MARGIN)),
		math.clamp(pan.Y, centre.Y - (maximum.Y + MARGIN), centre.Y - (minimum.Y - MARGIN))
	)
end

local function useSubscription<T>(read: () -> T, subscribe: (() -> ()) -> () -> ()): T
	local value, setValue = React.useState(read)
	React.useEffect(function()
		local disconnect = subscribe(function()
			setValue(read())
		end)
		setValue(read())
		return disconnect
	end, {})
	return value
end

-- 0..1 entrance progress, linear in time: forward over OPEN_TIME while open, back over CLOSE_TIME.
local function useReveal(open: boolean)
	local reveal, setReveal = React.useBinding(0)
	local current = React.useRef(0)
	React.useEffect(function()
		local target = if open then 1 else 0
		local rate = if open then 1 / OPEN_TIME else 1 / CLOSE_TIME
		local connection = RunService.Heartbeat:Connect(function(dt)
			local now = current.current :: number
			local nextValue = if target > now then math.min(target, now + rate * dt) else math.max(target, now - rate * dt)
			current.current = nextValue
			setReveal(nextValue)
		end)
		return function()
			connection:Disconnect()
		end
	end, { open })
	return reveal
end

local function TrackRow(props: { track: MasteryTracks.Track, level: number, current: boolean, layoutOrder: number })
	local theme = ThemeContext.useTheme()
	local hovered, setHovered = React.useState(false)
	local hover = useSpring(if hovered then 1 else 0, theme.motion.snap)
	local ink = if props.current then theme.color.accent else theme.color.textPrimary

	return e("TextButton", {
		Size = UDim2.fromOffset(236, 36),
		BackgroundColor3 = theme.color.surface,
		BackgroundTransparency = hover:map(function(h: number)
			return lerp(if props.current then 0.45 else 0.7, 0.35, h)
		end),
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = props.layoutOrder,
		[React.Event.MouseEnter] = function()
			setHovered(true)
			UISound.play("hover")
		end,
		[React.Event.MouseLeave] = function()
			setHovered(false)
		end,
		[React.Event.Activated] = function()
			if not props.current then
				UISound.play("confirm")
				MasteryCanvasController.setTrack(props.track.id)
			end
		end,
	}, {
		Frame = if props.current
			then e(Brackets, { size = "small", color = theme.color.accent, edgeTransparency = 0.6 })
			else nil,
		Icon = e("Frame", {
			Size = UDim2.fromOffset(20, 20),
			Position = UDim2.new(0, 12, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundTransparency = 1,
		}, {
			Glyph = e(Glyph, { glyph = props.track.glyph, color = ink, thickness = 1.25 }),
		}),
		Name = e("TextLabel", {
			Size = UDim2.new(1, -110, 1, 0),
			Position = UDim2.fromOffset(42, 0),
			BackgroundTransparency = 1,
			Text = string.upper(props.track.displayName),
			FontFace = theme.face.display,
			TextSize = theme.type.label,
			TextColor3 = ink,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
		Level = e("TextLabel", {
			Size = UDim2.new(0, 60, 1, 0),
			Position = UDim2.new(1, -12, 0, 0),
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 1,
			Text = `LV {props.level}`,
			FontFace = theme.face.mono,
			TextSize = theme.type.small,
			TextColor3 = if props.current then theme.color.accent else theme.color.textMuted,
			TextXAlignment = Enum.TextXAlignment.Right,
		}),
	})
end

local function MasteryCanvas()
	local theme = ThemeContext.useTheme()
	local canvas = useSubscription(MasteryCanvasController.get, MasteryCanvasController.onChanged)
	local progression = useSubscription(ProgressionClient.get, ProgressionClient.onChanged)
	local reveal = useReveal(canvas.open)

	local track = MasteryTracks.get(canvas.track) or MasteryTracks.list()[1]
	local levels = ProgressionClient.levels()
	local selectedShape = if progression then progression.shapes[track.classKey] else nil
	local tree = React.useMemo(function()
		return MasteryTree.build(track.id, levels, selectedShape)
	end, { track.id, progression } :: { any })
	local minimum, maximum = treeBounds(tree)

	local pan, setPan = React.useBinding(Vector2.zero)
	local panRef = React.useRef(Vector2.zero)
	local boundsRef = React.useRef({ minimum, maximum })
	boundsRef.current = { minimum, maximum }
	local dragRef = React.useRef(nil :: { origin: Vector2, start: Vector2? }?)

	local function applyPan(value: Vector2)
		local bounds = boundsRef.current :: { Vector2 }
		local clamped = clampPan(value, bounds[1], bounds[2])
		panRef.current = clamped
		setPan(clamped)
	end

	-- Opening, or switching track, frames the node in use.
	React.useEffect(function()
		if not canvas.open or not tree then
			return
		end
		local focusNode = tree.nodes[1]
		for _, node in ipairs(tree.nodes) do
			if node.selected then
				focusNode = node
			end
		end
		if focusNode then
			applyPan(viewSize() / 2 - (nodePosition(focusNode) + Node.SIZE / 2))
		end
	end, { canvas.open, track.id } :: { any })

	-- Dragging follows the pointer anywhere on screen once it has started on the field.
	React.useEffect(function()
		if not canvas.open then
			return
		end
		local moved = UserInputService.InputChanged:Connect(function(input)
			local drag = dragRef.current
			if not drag then
				return
			end
			if
				input.UserInputType ~= Enum.UserInputType.MouseMovement
				and input.UserInputType ~= Enum.UserInputType.Touch
			then
				return
			end
			local position = Vector2.new(input.Position.X, input.Position.Y)
			-- Measured from the first movement, in the same space as every later one: the press and
			-- the movement events disagree about where the top inset begins.
			if not drag.start then
				drag.start = position
				return
			end
			applyPan(drag.origin + (position - drag.start))
		end)
		local ended = UserInputService.InputEnded:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				dragRef.current = nil
			end
		end)
		return function()
			moved:Disconnect()
			ended:Disconnect()
			dragRef.current = nil
		end
	end, { canvas.open })

	local hud = reveal:map(function(r: number)
		return stage(r, 0.3, 0.6)
	end)
	local function hudFade(base: number)
		return hud:map(function(a: number)
			return 1 - (1 - base) * a
		end)
	end

	-- The field: grid, edges, nodes.
	local content: { [string]: any } = {}
	local gridFrom = minimum - Vector2.new(MARGIN, MARGIN)
	local gridTo = maximum + Vector2.new(MARGIN, MARGIN)
	local gx = math.floor(gridFrom.X / GRID_STEP) * GRID_STEP
	while gx <= gridTo.X do
		local gy = math.floor(gridFrom.Y / GRID_STEP) * GRID_STEP
		while gy <= gridTo.Y do
			content[`Grid{gx}_{gy}`] = e("Frame", {
				Size = UDim2.fromOffset(3, 3),
				Position = UDim2.fromOffset(gx, gy),
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundColor3 = theme.color.stroke,
				BackgroundTransparency = hud:map(function(a: number)
					return 1 - 0.14 * a
				end),
				BorderSizePixel = 0,
			})
			gy += GRID_STEP
		end
		gx += GRID_STEP
	end

	if tree then
		local byId: { [string]: MasteryTree.Node } = {}
		for _, node in ipairs(tree.nodes) do
			byId[node.id] = node
		end
		for _, edge in ipairs(tree.edges) do
			local parent, child = byId[edge.from], byId[edge.to]
			if parent and child then
				local from = nodePosition(parent) + Vector2.new(Node.SIZE.X, Node.SIZE.Y / 2)
				local to = nodePosition(child) + Vector2.new(0, Node.SIZE.Y / 2)
				content[`Edge{edge.from}_{edge.to}`] = e(Edge, {
					from = from,
					to = to,
					color = if child.selected then theme.color.accent else theme.color.stroke,
					background = theme.color.backdrop,
					strength = if child.visibility == "fogged" then 0.15 elseif child.unlocked then 0.65 else 0.35,
					appear = reveal:map(function(r: number)
						return columnStage(r, child.column)
					end),
				})
			end
		end
		for _, node in ipairs(tree.nodes) do
			content[`Node{node.id}`] = e(Node.render, {
				node = node,
				glyph = track.glyph,
				position = nodePosition(node),
				appear = reveal:map(function(r: number)
					return columnStage(r, node.column)
				end),
				onActivated = function()
					if not node.unlocked then
						UISound.play("error")
						return
					end
					if node.selected then
						return
					end
					ProgressionClient.selectShape(track.classKey, if node.isDefault then "" else node.id)
				end,
			})
		end
	end

	local progress = progression and progression.masteries[track.id]
	local level = if progress then progress.level else 0
	local xp = if progress then progress.xp else 0
	local needed = MasteryTracks.xpToNext(level)

	local trackRows: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		}),
	}
	for index, entry in ipairs(MasteryTracks.list()) do
		local entryProgress = progression and progression.masteries[entry.id]
		trackRows[entry.id] = e(TrackRow, {
			track = entry,
			level = if entryProgress then entryProgress.level else 0,
			current = entry.id == track.id,
			layoutOrder = index,
		})
	end

	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = reveal:map(function(r: number)
			return r > 0
		end),
	}, {
		Backdrop = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = theme.color.backdrop,
			BackgroundTransparency = reveal:map(function(r: number)
				return lerp(1, 0.25, stage(r, 0, 0.35))
			end),
			BorderSizePixel = 0,
			ZIndex = 1,
		}),

		-- The field takes every press that lands on it (and not on a node), which is how the world
		-- behind stays out of reach and how a drag starts.
		Field = e("TextButton", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = "",
			ClipsDescendants = true,
			ZIndex = 2,
			[React.Event.MouseButton1Down] = function()
				dragRef.current = { origin = panRef.current :: Vector2, start = nil }
			end,
		}, {
			Content = e("Frame", {
				Size = UDim2.fromOffset(0, 0),
				Position = pan:map(function(value: Vector2)
					return UDim2.fromOffset(value.X, value.Y)
				end),
				BackgroundTransparency = 1,
			}, content),
		}),

		ScanLine = e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = reveal:map(function(r: number)
				return UDim2.new(0.92 * stage(r, 0.04, 0.32), 0, 0, 2)
			end),
			BackgroundColor3 = theme.color.stroke,
			BackgroundTransparency = reveal:map(function(r: number)
				return lerp(0, 1, Ease.clamp01((r - 0.36) / 0.22))
			end),
			BorderSizePixel = 0,
			ZIndex = 8,
		}),

		Header = e("Frame", {
			Size = UDim2.fromOffset(460, 120),
			Position = UDim2.fromOffset(56, 48),
			BackgroundTransparency = 1,
			ZIndex = 10,
		}, {
			Kicker = e("TextLabel", {
				Size = UDim2.fromOffset(300, 16),
				BackgroundTransparency = 1,
				Text = "MASTERY",
				FontFace = theme.face.display,
				TextSize = theme.type.label,
				TextColor3 = theme.color.textMuted,
				TextTransparency = hudFade(0),
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Icon = e("Frame", {
				Size = UDim2.fromOffset(34, 34),
				Position = UDim2.fromOffset(0, 26),
				BackgroundTransparency = 1,
			}, {
				Glyph = e(Glyph, { glyph = track.glyph, color = theme.color.textHeading, thickness = 1.5 }),
			}),
			Title = e("TextLabel", {
				Size = UDim2.fromOffset(400, 36),
				Position = UDim2.fromOffset(46, 25),
				BackgroundTransparency = 1,
				Text = string.upper(track.displayName),
				FontFace = theme.face.display,
				TextSize = 30,
				TextColor3 = theme.color.textHeading,
				TextTransparency = hudFade(0),
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Level = e("TextLabel", {
				Size = UDim2.fromOffset(80, 22),
				Position = UDim2.fromOffset(0, 74),
				BackgroundTransparency = 1,
				Text = `LV {level}`,
				FontFace = theme.face.mono,
				TextSize = theme.type.title,
				TextColor3 = theme.color.textPrimary,
				TextTransparency = hudFade(0),
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			BarTrack = e("Frame", {
				Size = UDim2.fromOffset(260, 2),
				Position = UDim2.fromOffset(86, 84),
				BackgroundColor3 = theme.color.stroke,
				BackgroundTransparency = hudFade(0.8),
				BorderSizePixel = 0,
			}, {
				Fill = e("Frame", {
					Size = UDim2.fromScale(if needed then math.clamp(xp / needed, 0, 1) else 1, 1),
					BackgroundColor3 = theme.color.accent,
					BackgroundTransparency = hudFade(0),
					BorderSizePixel = 0,
				}),
			}),
			Xp = e("TextLabel", {
				Size = UDim2.fromOffset(260, 16),
				Position = UDim2.fromOffset(86, 92),
				BackgroundTransparency = 1,
				Text = if needed then `{xp} / {needed} XP` else "MAX",
				FontFace = theme.face.mono,
				TextSize = theme.type.label,
				TextColor3 = theme.color.textMuted,
				TextTransparency = hudFade(0),
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
		}),

		Tracks = e("CanvasGroup", {
			Size = UDim2.fromOffset(236, 4 * 42),
			Position = UDim2.new(1, -56, 0, 48),
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 1,
			GroupTransparency = hudFade(0),
			ZIndex = 10,
		}, trackRows),

		Close = e("CanvasGroup", {
			Size = UDim2.fromOffset(120, 34),
			Position = UDim2.new(1, -56, 1, -48),
			AnchorPoint = Vector2.new(1, 1),
			BackgroundTransparency = 1,
			GroupTransparency = hudFade(0),
			ZIndex = 10,
		}, {
			Button = e(Button, {
				text = "CLOSE  [M]",
				variant = "secondary",
				size = UDim2.fromScale(1, 1),
				textSize = theme.type.label,
				onActivated = MasteryCanvasController.close,
			}),
		}),

		Hint = e("TextLabel", {
			Size = UDim2.fromOffset(640, 18),
			Position = UDim2.new(0.5, 0, 1, -56),
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundTransparency = 1,
			Text = "DRAG TO MOVE   ·   CHOOSE AN UNLOCKED FORM TO USE IT",
			FontFace = theme.face.display,
			TextSize = theme.type.label,
			TextColor3 = theme.color.textMuted,
			TextTransparency = hudFade(0.2),
			ZIndex = 10,
		}),
	})
end

return MasteryCanvas
