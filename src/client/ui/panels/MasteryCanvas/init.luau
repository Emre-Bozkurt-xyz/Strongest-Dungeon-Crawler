--!strict
-- The mastery mind-space (docs/planning/mastery-mind-space.md): a starfield on near-black holding
-- the mastery menu, which zooms into one mastery's tree. The tree is laid out left to right on an
-- open field the player drags around.
--
-- An airy void rather than a scrolling panel: the tree sits in space with a faint grid to show it
-- moving, and the view is bounded so it can drift past the tree's edge but never lose it. Fog is the
-- tree model's (MasteryTree): only one or two nodes past what the player has reached are drawn.
--
-- At an Attunement Shrine (MasteryCanvasController's shrine mode) choosing a box in the menu opens
-- the shrine's confirmation (ShrineDialog) instead of the tree.
--
-- Entrance, as one 0..1 progress: the world goes dark, a line of light draws across the screen and
-- fades, and the menu comes up. Closing runs it backward, faster. Between menu and tree a second
-- 0..1 (depth) zooms: the menu swells and fades as the tree comes in from smaller.
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
local MasteryXP = require(ReplicatedStorage.Shared.progression.MasteryXP)
local Ease = require(ReplicatedStorage.Shared.ui.Ease)

local ThemeContext = require(script.Parent.Parent.hooks.ThemeContext)
local useSpring = require(script.Parent.Parent.hooks.useSpring)
local Button = require(script.Parent.Parent.components.Button)
local Glyph = require(script.Parent.Parent.components.Glyph)
local UISound = require(script.Parent.Parent.UISound)
local MasteryCanvasController = require(script.Parent.Parent.controllers.MasteryCanvasController)
local ProgressionClient = require(script.Parent.Parent.Parent.Progression.ProgressionClient)
local Node = require(script.Node)
local Edge = require(script.Edge)
local Menu = require(script.Menu)
local ShrineDialog = require(script.ShrineDialog)
local Starfield = require(script.Starfield)

local e = React.createElement

-- Pixels between nodes, across columns and down rows.
local GAP = Vector2.new(96, 36)
-- How far past the tree's edge the view's centre may travel.
local MARGIN = 320
-- Spacing of the faint grid that shows the field moving.
local GRID_STEP = 120
-- Where across the screen the node in use is framed on opening, as a fraction of its width.
local FOCUS_X = 0.3

local OPEN_TIME = 0.55
local CLOSE_TIME = 0.18
-- The mind-space's black, and how much of the world shows through it.
local VOID = Color3.fromRGB(4, 5, 8)
local VOID_TRANSPARENCY = 0.06

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

local function MasteryCanvas()
	local theme = ThemeContext.useTheme()
	local canvas = useSubscription(MasteryCanvasController.get, MasteryCanvasController.onChanged)
	local progression = useSubscription(ProgressionClient.get, ProgressionClient.onChanged)
	local reveal = useReveal(canvas.open)
	local inTree = canvas.view == "tree"
	local depth = useSpring(if inTree then 1 else 0, theme.motion.settle)
	local dialog, setDialog = React.useState(nil :: string?)
	local atShrine = canvas.shrine ~= nil
	-- The shrine's dialog belongs to the shrine and the menu: leaving either drops it.
	React.useEffect(function()
		if not canvas.open or not atShrine or inTree then
			setDialog(nil)
		end
	end, { canvas.open, atShrine, inTree } :: { any })

	local track = MasteryTracks.get(canvas.track) or MasteryTracks.list()[1]
	local context = MasteryCanvasController.context()
	local branches = ProgressionClient.branches(track.id)
	local selectedShape = if progression then progression.shapes[context] else nil
	local attuned = ProgressionClient.isAttuned(track.id)
	local tree = React.useMemo(function()
		-- The form in effect, so infusion nodes show which is in use and every node can name the
		-- combination it would make with the other half.
		local pairing = if progression
			then MasteryTree.pairingFor(
				context,
				progression.shapes,
				progression.infusion,
				progression.masteries,
				progression.attunement
			)
			else nil
		if pairing then
			pairing.passives = ProgressionClient.chosenPassives()
		end
		return MasteryTree.build(track.id, branches, context, selectedShape, attuned, pairing)
	end, { track.id, progression, context } :: { any })
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
			-- Left of centre: trees grow rightward, and the track list sits at the top right.
			local view = viewSize()
			local anchor = Vector2.new(view.X * FOCUS_X, view.Y / 2)
			applyPan(anchor - (nodePosition(focusNode) + Node.SIZE / 2))
		end
	end, { canvas.open, track.id, canvas.view } :: { any })

	-- Dragging follows the pointer anywhere on screen once it has started on the field.
	React.useEffect(function()
		if not canvas.open or not inTree then
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
	end, { canvas.open, inTree } :: { any })

	local hud = React.joinBindings({ reveal = reveal, depth = depth }):map(function(values: { reveal: number, depth: number })
		return stage(values.reveal, 0.3, 0.6) * Ease.clamp01(values.depth)
	end)
	local menuPresence = React.joinBindings({ reveal = reveal, depth = depth }):map(
		function(values: { reveal: number, depth: number })
			return stage(values.reveal, 0.3, 0.6) * (1 - Ease.clamp01(values.depth))
		end
	)
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
					-- An infusion toggles: there is one or none, so choosing the one in use clears it.
					if node.kind == "infusion" then
						if not node.selectable then
							UISound.play("error")
							return
						end
						ProgressionClient.selectInfusion(if node.selected then "" else node.id)
						return
					end
					-- A selectable passive toggles in and out of the shared slots.
					if node.kind == "select" then
						if not node.selectable then
							UISound.play("error")
							return
						end
						ProgressionClient.selectPassive(node.id, not node.selected)
						return
					end
					-- Only an unlocked form that has a profile for the held weapon can be chosen.
					local shapeId = node.shapeId
					if not node.unlocked or node.dormant or node.kind ~= "form" or not shapeId then
						UISound.play("error")
						return
					end
					if node.selected then
						return
					end
					ProgressionClient.selectShape(context, if node.isDefault then "" else shapeId)
				end,
			})
		end
	end

	local progress = MasteryXP.progressOf(MasteryXP.totalOf(branches))
	local level = progress.level
	local xp = math.floor(progress.into)
	local needed = progress.needed

	-- One line per branch: how far along it is, or that it is Mastered.
	local branchParts: { string } = {}
	if tree then
		for _, branch in ipairs({ "trunk", "a", "b" }) do
			local entry = tree.branches[branch]
			if entry then
				local amount = if entry.mastered then "MASTERED" else `{math.floor(entry.xp)}/{entry.cap}`
				table.insert(branchParts, `{string.upper(entry.name)} {amount}`)
			end
		end
	end

	local attunementLine = if attuned
		then `{string.upper(track.displayName)} IS ATTUNED`
		elseif track.family == "attack" then "DORMANT  ·  ONLY ITS ROOT FORM WORKS UNTIL ATTUNED AT A SHRINE"
		else "ATTUNING IT AT A SHRINE STRENGTHENS IT"

	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = reveal:map(function(r: number)
			return r > 0
		end),
	}, {
		Backdrop = e("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = VOID,
			BackgroundTransparency = reveal:map(function(r: number)
				return lerp(1, VOID_TRANSPARENCY, stage(r, 0, 0.35))
			end),
			BorderSizePixel = 0,
			ZIndex = 1,
		}),

		Stars = e(Starfield, {
			active = canvas.open,
			presence = reveal:map(function(r: number)
				return stage(r, 0.2, 0.7)
			end),
			zIndex = 1,
		}),

		-- The menu swells and fades as the tree comes in.
		MenuGroup = e("CanvasGroup", {
			Size = UDim2.fromScale(1, 1),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			GroupTransparency = menuPresence:map(function(p: number)
				return 1 - p
			end),
			Visible = menuPresence:map(function(p: number)
				return p > 0.01
			end),
			ZIndex = 3,
		}, {
			Scale = e("UIScale", {
				Scale = depth:map(function(d: number)
					return 1 + 0.35 * Ease.clamp01(d)
				end),
			}),
			Menu = e(Menu, {
				shrine = atShrine,
				context = context,
				onChoose = function(trackId: string)
					if inTree then
						return
					end
					if atShrine then
						UISound.play("hover")
						setDialog(trackId)
					else
						UISound.play("confirm")
						MasteryCanvasController.setTrack(trackId)
					end
				end,
			}),
		}),

		Dialog = if dialog
			then e(ShrineDialog, {
				trackId = dialog,
				onClose = function()
					setDialog(nil)
				end,
				onAttuned = function() end,
			})
			else nil,

		-- The tree comes in from smaller as the menu falls away.
		TreeGroup = e("CanvasGroup", {
			Size = UDim2.fromScale(1, 1),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			GroupTransparency = depth:map(function(d: number)
				return 1 - Ease.clamp01(d)
			end),
			Visible = depth:map(function(d: number)
				return d > 0.01
			end),
			ZIndex = 2,
		}, {
			Scale = e("UIScale", {
				Scale = depth:map(function(d: number)
					return lerp(0.8, 1, Ease.clamp01(d))
				end),
			}),
			-- The field takes every press that lands on it (and not on a node), which is how the world
			-- behind stays out of reach and how a drag starts.
			Field = e("TextButton", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				AutoButtonColor = false,
				Text = "",
				ClipsDescendants = true,
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
		}),

		-- Takes presses on the empty sky in the menu, so the world behind stays out of reach.
		Shield = e("TextButton", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Text = "",
			Visible = not inTree,
			ZIndex = 2,
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
			Size = UDim2.fromOffset(560, 164),
			Position = UDim2.fromOffset(56, 48),
			BackgroundTransparency = 1,
			Visible = inTree,
			ZIndex = 10,
		}, {
			Kicker = e("TextLabel", {
				Size = UDim2.fromOffset(300, 16),
				BackgroundTransparency = 1,
				Text = if atShrine then "ATTUNEMENT SHRINE" else "MASTERY",
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
			Branches = e("TextLabel", {
				Size = UDim2.fromOffset(460, 16),
				Position = UDim2.fromOffset(0, 120),
				BackgroundTransparency = 1,
				Text = table.concat(branchParts, "   ·   "),
				FontFace = theme.face.mono,
				TextSize = theme.type.label,
				TextColor3 = theme.color.textMuted,
				TextTransparency = hudFade(0),
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Attunement = e("TextLabel", {
				Size = UDim2.fromOffset(560, 16),
				Position = UDim2.fromOffset(0, 144),
				BackgroundTransparency = 1,
				Text = attunementLine,
				FontFace = theme.face.display,
				TextSize = theme.type.label,
				TextColor3 = if attuned then theme.color.accent else theme.color.textMuted,
				TextTransparency = hudFade(0),
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
		}),

		Close = e("CanvasGroup", {
			Size = UDim2.fromOffset(120, 34),
			Position = UDim2.new(1, -56, 1, -48),
			AnchorPoint = Vector2.new(1, 1),
			BackgroundTransparency = 1,
			GroupTransparency = reveal:map(function(r: number)
				return 1 - stage(r, 0.3, 0.6)
			end),
			ZIndex = 10,
		}, {
			Button = e(Button, {
				text = if inTree then "BACK" else "CLOSE  [M]",
				variant = "secondary",
				size = UDim2.fromScale(1, 1),
				textSize = theme.type.label,
				onActivated = if inTree then MasteryCanvasController.back else MasteryCanvasController.close,
			}),
		}),

		Hint = e("TextLabel", {
			Size = UDim2.fromOffset(640, 18),
			Position = UDim2.new(0.5, 0, 1, -56),
			AnchorPoint = Vector2.new(0.5, 1),
			BackgroundTransparency = 1,
			Text = "DRAG TO MOVE   /   CHOOSE AN UNLOCKED FORM, INFUSION OR SELECTABLE PASSIVE TO USE IT",
			FontFace = theme.face.display,
			TextSize = theme.type.label,
			TextColor3 = theme.color.textMuted,
			TextTransparency = hudFade(0.2),
			ZIndex = 10,
		}),
	})
end

return MasteryCanvas
