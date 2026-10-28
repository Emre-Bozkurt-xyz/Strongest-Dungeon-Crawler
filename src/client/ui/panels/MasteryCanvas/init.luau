--!strict
-- The mastery mind-space (docs/planning/mastery-mind-space.md): a starfield on near-black holding
-- the mastery menu, which zooms into one mastery's tree. The tree is a constellation growing left
-- to right, on a field the player drags around.
--
-- The view is bounded so it can drift past the tree's edge but never lose it, and the sky drifts a
-- little with it so the field reads as moving. Fog is the tree model's (MasteryTree): the next node
-- along a line is drawn in full, the one after only as a faint star.
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
local UISound = require(script.Parent.Parent.UISound)
local MasteryCanvasController = require(script.Parent.Parent.controllers.MasteryCanvasController)
local ProgressionClient = require(script.Parent.Parent.Parent.Progression.ProgressionClient)
local Node = require(script.Node)
local Edge = require(script.Edge)
local Menu = require(script.Menu)
local ShrineDialog = require(script.ShrineDialog)
local Starfield = require(script.Starfield)
local Tooltip = require(script.Tooltip)
local Burst = require(script.Burst)

local e = React.createElement

-- The constellation's spacing: pixels between ranks, and how far each rank of branches "a" (above)
-- and "b" (below) sits from the trunk. Branches bow outward and back in toward the join.
local COLUMN = 255
local BRANCH_RISE = { 0, 190, 255, 275, 238 }
-- How far a node may stray from its place, so the tree reads as stars rather than a grid.
local JITTER = 34
-- How far past the tree's edge the view's centre may travel.
local MARGIN = 260
-- Where across the screen the node in use is framed on opening, as a fraction of its width.
local FOCUS_X = 0.32
-- How much the sky drifts with a drag, as a share of the drag.
local SKY_DRIFT = 0.04

local OPEN_TIME = 0.55
local CLOSE_TIME = 0.18
-- The mind-space's black, and how much of the world shows through it.
local VOID = Color3.fromRGB(4, 5, 8)
local VOID_TRANSPARENCY = 0.06
local INK = Color3.fromRGB(238, 241, 246)

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

-- 0..1, fixed per string: a node's stray from its place is the same every time it is drawn.
local function hash(text: string): number
	local h = 2166136261
	for index = 1, #text do
		h = bit32.bxor(h, string.byte(text, index))
		h = (h * 16777619) % 4294967296
	end
	return (h % 1000) / 1000
end

local function nodePosition(node: MasteryTree.Node): Vector2
	local function jitter(axis: string): number
		return (hash(node.id .. axis) - 0.5) * JITTER
	end
	local rank = node.rank
	if node.branch == "trunk" then
		if rank == 0 then
			return Vector2.zero
		end
		return Vector2.new(rank * COLUMN * 0.92 + jitter("x"), jitter("y") * 0.6)
	elseif node.branch == "a" or node.branch == "b" then
		local rise = BRANCH_RISE[rank + 1] or BRANCH_RISE[#BRANCH_RISE]
		return Vector2.new(rank * COLUMN + jitter("x"), (if node.branch == "a" then -rise else rise) + jitter("y"))
	elseif node.branch == "join" then
		return Vector2.new(5 * COLUMN + 16, 0)
	end
	return Vector2.new(6 * COLUMN + 32, 0)
end

-- An instance name for a node id: dots would read as path separators to tools that find it.
local function key(nodeId: string): string
	return (string.gsub(nodeId, "%.", "_"))
end

local function treeBounds(tree: MasteryTree.Tree?): (Vector2, Vector2)
	if not tree or #tree.nodes == 0 then
		return Vector2.zero, Vector2.zero
	end
	local minimum, maximum = Vector2.new(math.huge, math.huge), Vector2.new(-math.huge, -math.huge)
	for _, node in ipairs(tree.nodes) do
		local position = nodePosition(node)
		minimum = minimum:Min(position)
		maximum = maximum:Max(position)
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

-- A second click on a pinned node this soon after pinning it is the tail of a reflexive
-- double-click, not a decision: it only opens the node.
local DOUBLE_CLICK_GUARD = 0.3

-- What a second click on a node does, and the standing it already has.
type NodeAction = { label: string, enabled: boolean, run: (() -> ())?, sound: string }

local function actionFor(node: MasteryTree.Node, context: string): (NodeAction?, string?)
	if not node.unlocked then
		return nil, nil
	end
	if node.kind == "form" then
		if node.selected then
			return nil, "IN USE"
		end
		local shapeId = node.shapeId
		if node.dormant or not shapeId then
			return { label = "USE THIS FORM", enabled = false, sound = "error" }, nil
		end
		return {
			label = "USE THIS FORM",
			enabled = true,
			sound = "formEquip",
			run = function()
				ProgressionClient.selectShape(context, if node.isDefault then "" else shapeId)
			end,
		}, nil
	elseif node.kind == "infusion" then
		-- An infusion toggles: there is one or none, so choosing the one in use clears it.
		return {
			label = if node.selected then "REMOVE INFUSION" else "INFUSE",
			enabled = node.selectable,
			sound = "formEquip",
			run = function()
				ProgressionClient.selectInfusion(if node.selected then "" else node.id)
			end,
		}, if node.selected then "IN USE" else nil
	elseif node.kind == "select" then
		-- A selectable passive toggles in and out of the shared slots.
		return {
			label = if node.selected then "RELEASE" else "CHOOSE",
			enabled = node.selectable,
			sound = "nodeSelect",
			run = function()
				ProgressionClient.selectPassive(node.id, not node.selected)
			end,
		}, if node.selected then "CHOSEN" else nil
	end
	return nil, if node.dormant then "DORMANT" else "ACTIVE"
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
	local celebrate, setCelebrate = React.useState(nil :: { track: string, id: number }?)
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
	local dragRef = React.useRef(nil :: { origin: Vector2, start: Vector2?, moved: boolean }?)
	-- The node under the pointer, and the node pinned by a click (with when it was pinned).
	local hoveredId, setHoveredId = React.useState(nil :: string?)
	local pinned, setPinned = React.useState(nil :: { id: string, at: number }?)
	local bursts, setBursts = React.useState({} :: { { id: number, position: Vector2 } })
	local burstCount = React.useRef(0)

	local function burstAt(position: Vector2)
		burstCount.current = (burstCount.current :: number) + 1
		local id = burstCount.current :: number
		setBursts(function(current)
			local nextBursts = table.clone(current)
			table.insert(nextBursts, { id = id, position = position })
			return nextBursts
		end)
	end
	local function removeBurst(id: number)
		setBursts(function(current)
			local nextBursts = {}
			for _, burst in ipairs(current) do
				if burst.id ~= id then
					table.insert(nextBursts, burst)
				end
			end
			return nextBursts
		end)
	end

	-- A tooltip belongs to the tree it was opened in.
	React.useEffect(function()
		setPinned(nil)
		setHoveredId(nil)
	end, { canvas.open, track.id, canvas.view } :: { any })

	local function applyPan(value: Vector2)
		local bounds = boundsRef.current :: { Vector2 }
		local clamped = clampPan(value, bounds[1], bounds[2])
		panRef.current = clamped
		setPan(clamped)
	end

	-- Opening, or switching track, frames the node in use, or the node a link asked for (pinned, so
	-- its details are already showing).
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
		for _, node in ipairs(tree.nodes) do
			if node.id == canvas.focus and node.visibility ~= "fogged" then
				focusNode = node
				setPinned({ id = node.id, at = os.clock() })
			end
		end
		if focusNode then
			-- Left of centre: trees grow rightward.
			local view = viewSize()
			local anchor = Vector2.new(view.X * FOCUS_X, view.Y / 2)
			applyPan(anchor - nodePosition(focusNode))
		end
	end, { canvas.open, track.id, canvas.view, canvas.focus } :: { any })

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
			local offset = position - (drag.start :: Vector2)
			if offset.Magnitude > 4 then
				drag.moved = true
			end
			applyPan(drag.origin + offset)
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

	-- One clock for every pulse, running only while a tree is shown.
	local clock, setClock = React.useBinding(0)
	React.useEffect(function()
		if not canvas.open or not inTree then
			return
		end
		local elapsed = 0
		local connection = RunService.Heartbeat:Connect(function(dt)
			elapsed += dt
			setClock(elapsed)
		end)
		return function()
			connection:Disconnect()
		end
	end, { canvas.open, inTree } :: { any })

	-- The constellation: lines under, nodes over.
	local content: { [string]: any } = {}
	local tooltip: any = nil
	if tree then
		local byId: { [string]: MasteryTree.Node } = {}
		for _, node in ipairs(tree.nodes) do
			byId[node.id] = node
		end
		for _, edge in ipairs(tree.edges) do
			local parent, child = byId[edge.from], byId[edge.to]
			if parent and child then
				local state: Edge.State
				if child.visibility == "fogged" then
					state = "fogged"
				elseif child.unlocked and parent.unlocked then
					-- Lines into the join and end belong to no one branch, so they never glow.
					local branch = tree.branches[child.branch]
					state = if branch and branch.mastered then "mastered" else "earned"
				else
					state = "pending"
				end
				content[`Edge_{key(edge.from)}_{key(edge.to)}`] = e(Edge, {
					from = nodePosition(parent),
					to = nodePosition(child),
					state = state,
					-- Only a line out of an open node fills: the one beyond it has nothing to fill from.
					fill = if parent.unlocked then child.progress else 0,
					appear = depth:map(function(d: number)
						return columnStage(d, child.column)
					end),
				})
			end
		end
		for _, node in ipairs(tree.nodes) do
			content[`Node_{key(node.id)}`] = e(Node.render, {
				node = node,
				trackId = track.id,
				position = nodePosition(node),
				unseen = node.unlocked and progression ~= nil and progression.unseen[node.id] == true,
				appear = depth:map(function(d: number)
					return columnStage(d, node.column)
				end),
				clock = clock,
				onHover = function()
					setHoveredId(node.id)
					-- Looking at a new node is reading it.
					if node.unlocked then
						ProgressionClient.markSeen(node.id)
					end
				end,
				onLeave = function()
					setHoveredId(function(current)
						return if current == node.id then nil else current
					end)
				end,
				-- The first click pins the tooltip; a second click on the pinned node acts.
				onActivated = function()
					if not pinned or pinned.id ~= node.id then
						UISound.play("nodePin")
						setPinned({ id = node.id, at = os.clock() })
						return
					end
					if os.clock() - pinned.at < DOUBLE_CLICK_GUARD then
						return
					end
					local action = actionFor(node, context)
					if not action then
						return
					end
					if not action.enabled or not action.run then
						UISound.play("error")
						return
					end
					UISound.play(action.sound)
					burstAt(nodePosition(node))
					action.run()
				end,
			})
		end
	end
	for _, burst in ipairs(bursts) do
		content[`Burst{burst.id}`] = e(Burst, {
			position = burst.position,
			seed = burst.id,
			color = if track.color then Color3.new(1, 1, 1):Lerp(track.color, 0.5) else nil,
			onDone = function()
				removeBurst(burst.id)
			end,
		})
	end

	-- The tooltip: the pinned node's, else the hovered node's.
	local shownId = if pinned then pinned.id else hoveredId
	for _, node in ipairs(if tree then tree.nodes else {}) do
		if node.id == shownId and node.visibility ~= "fogged" then
			local action, state = actionFor(node, context)
			local position = nodePosition(node)
			tooltip = e(Tooltip, {
				node = node,
				trackId = track.id,
				branches = branches,
				attuned = attuned,
				pinned = pinned ~= nil and pinned.id == node.id,
				action = if action then { label = action.label, enabled = action.enabled } else nil,
				state = state,
				anchor = pan:map(function(value: Vector2)
					return value + position
				end),
				reach = Node.reachOf(node.kind),
			})
		end
	end

	local level = MasteryXP.levelOf(MasteryXP.totalOf(branches))
	local treeName = `{string.upper(track.displayName)}  ·  LV {level}`
	if attuned then
		treeName ..= "  ·  ATTUNED"
	elseif track.family == "attack" then
		treeName ..= "  ·  DORMANT"
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
			BackgroundColor3 = VOID,
			BackgroundTransparency = reveal:map(function(r: number)
				return lerp(1, VOID_TRANSPARENCY, stage(r, 0, 0.35))
			end),
			BorderSizePixel = 0,
			ZIndex = 1,
		}),

		-- Slightly larger than the screen so its drift with a drag never shows an edge.
		Sky = e("Frame", {
			Size = UDim2.fromScale(1.1, 1.1),
			Position = pan:map(function(value: Vector2)
				local drift = value * SKY_DRIFT
				return UDim2.new(0.5, math.clamp(drift.X, -60, 60), 0.5, math.clamp(drift.Y, -40, 40))
			end),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			ZIndex = 1,
		}, {
			Stars = e(Starfield, {
				active = canvas.open,
				tint = if inTree then track.color else nil,
				presence = reveal:map(function(r: number)
					return stage(r, 0.2, 0.7)
				end),
			}),
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
				celebrate = celebrate,
				onCelebrated = function()
					setCelebrate(nil)
				end,
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
				onAttuned = function(trackId: string)
					burstCount.current = (burstCount.current :: number) + 1
					setCelebrate({ track = trackId, id = burstCount.current :: number })
				end,
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
					dragRef.current = { origin = panRef.current :: Vector2, start = nil, moved = false }
				end,
				-- A click on empty sky (not the end of a drag) lets go of a pinned tooltip.
				[React.Event.Activated] = function()
					local drag = dragRef.current
					if not (drag and drag.moved) then
						setPinned(nil)
					end
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

		Tooltip = if inTree and tooltip
			then e("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ZIndex = 20,
			}, { Tip = tooltip })
			else nil,

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

		-- The tree carries everything else: here only the way back and which tree this is.
		TreeTop = e("Frame", {
			Size = UDim2.fromOffset(480, 60),
			-- Below Roblox's top bar, which covers the top of a full-screen layer.
			Position = UDim2.fromOffset(56, 96),
			BackgroundTransparency = 1,
			Visible = inTree,
			ZIndex = 10,
		}, {
			Back = e("TextButton", {
				AutomaticSize = Enum.AutomaticSize.X,
				Size = UDim2.fromOffset(0, 24),
				BackgroundTransparency = 1,
				Text = "‹   MASTERIES",
				FontFace = theme.face.display,
				TextSize = 13,
				TextColor3 = INK,
				TextTransparency = hudFade(0.3),
				TextXAlignment = Enum.TextXAlignment.Left,
				[React.Event.MouseEnter] = function()
					UISound.play("hover")
				end,
				[React.Event.Activated] = MasteryCanvasController.back,
			}),
			Name = e("TextLabel", {
				Size = UDim2.fromOffset(480, 20),
				Position = UDim2.fromOffset(0, 36),
				BackgroundTransparency = 1,
				Text = treeName,
				FontFace = theme.face.display,
				TextSize = 15,
				TextColor3 = INK,
				TextTransparency = hudFade(0.28),
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
			Text = "DRAG TO MOVE",
			FontFace = theme.face.display,
			TextSize = 10,
			TextColor3 = INK,
			TextTransparency = hudFade(0.6),
			ZIndex = 10,
		}),
	})
end

return MasteryCanvas
