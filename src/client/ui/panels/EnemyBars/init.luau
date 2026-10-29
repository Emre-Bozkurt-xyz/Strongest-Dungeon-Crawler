--!strict
-- Health bars over revealed enemies: name, a segmented bar in the danger colour that leaves a trail of
-- the cells a hit took, and the exact health or, when only that is revealed, a percentage.
--
-- Under the bar, a mark for each status effect the enemy carries, from the left edge in the order
-- they arrived: a square with the effect's glyph, and its stack count when it has more than one. The
-- square's white outline is its timer: whole when the effect is applied, giving way clockwise from
-- the top as it runs out. Timers run on the server's clock, so they need no updates to count down.
--
-- The value is always the server's. A predicted hit only jolts the bar sideways, so the strike
-- registers on the frame it lands and the cells drop when the server confirms the damage.
--
-- Screen UI placed over each enemy's projected position, like the loot plates and the vitals: one
-- size at any distance, drawn over effects. The nearest few stay at full strength and the rest step
-- down, so a crowd stays readable. Hidden while a menu is open.
--
-- `script` here IS the EnemyBars module (init.luau collapses into its folder), so Parent is `panels`
-- and Parent.Parent is `ui`.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local React = require(ReplicatedStorage.Packages.React)
local Clock = require(ReplicatedStorage.Shared.Time.Clock)

local EntityStore = require(script.Parent.Parent.Parent.Entities.EntityStore)
local Glyph = require(script.Parent.Parent.components.Glyph)
local SegmentedGauge = require(script.Parent.Parent.components.SegmentedGauge)
local StatusLooks = require(script.StatusLooks)
local ThemeContext = require(script.Parent.Parent.hooks.ThemeContext)
local useMenuState = require(script.Parent.Parent.hooks.useMenuState)
local useOverlayOpen = require(script.Parent.Parent.hooks.useOverlayOpen)

local e = React.createElement

-- Studs above the enemy's root.
local HEIGHT = 3.0
-- Pixels. Sized for a glance at a moving target: the name and health have to read at once over any
-- background, so they are a step larger and heavier than panel text, with a solid outline.
local SIZE = Vector2.new(176, 36)
-- Bars past this many, nearest first, step down in strength.
local FULL_COUNT = 6
local MIN_STRENGTH = 0.3
-- Alpha per second: a bar cuts in or out in about a tenth of a second.
local ALPHA_RATE = 10
-- Jolt on a predicted strike: pixels at its peak, seconds to settle, and oscillation rate.
local JOLT_PIXELS = 4
local JOLT_DURATION = 0.18
local JOLT_FREQUENCY = 45
-- Status marks, in pixels: the square, the space between squares and below the bar, the outline.
local MARK = 26
local MARK_GAP = 4
local MARK_TOP = 5
local MARK_STROKE = 2
local MARK_GLYPH = 16
local MAX_MARKS = 6
-- The untimed part of the outline, so how much is left reads against the whole.
local MARK_TRACK_TRANSPARENCY = 0.8
-- Experiment: the seconds left as text in the square.
local SHOW_SECONDS = false
-- The bar keeps its place over the enemy; the marks hang below it, and a stack count below their
-- corner.
local STACKS_OVERHANG = 4
local FRAME = Vector2.new(SIZE.X, SIZE.Y + MARK_TOP + MARK + STACKS_OVERHANG)

type Placement = { position: Vector2, alpha: number }

local function revealed(): { EntityStore.Entry }
	local list = {}
	for _, entry in ipairs(EntityStore.getSnapshot()) do
		if entry.health then
			table.insert(list, entry)
		end
	end
	return list
end

local function useEnemyHealth(): { EntityStore.Entry }
	local entries, setEntries = React.useState(revealed)
	React.useEffect(function()
		local disconnect = EntityStore.onChanged(function()
			setEntries(revealed())
		end)
		setEntries(revealed())
		return disconnect
	end, {})
	return entries
end

local function joltOffset(id: string, now: number): number
	local struck = EntityStore.getStruckAt(id)
	local age = if struck then now - struck else math.huge
	if age >= JOLT_DURATION then
		return 0
	end
	local decay = 1 - age / JOLT_DURATION
	return math.round(math.sin(age * JOLT_FREQUENCY) * JOLT_PIXELS * decay * decay)
end

-- The outline's runs, clockwise from the top centre: where each starts along the perimeter and how
-- long it is, in sides.
local RUN_STARTS = { 0, 0.5, 1.5, 2.5, 3.5 }
local RUN_LENGTHS = { 0.5, 1, 1, 1, 0.5 }

-- One run of the outline with `remaining` (0..1) of the timer left: the part already gone is taken
-- from the start of the perimeter, so the gap opens at the top and sweeps clockwise.
local function outlineRun(index: number, remaining: number): (UDim2, UDim2)
	local side, thickness = MARK, MARK_STROKE
	local length = RUN_LENGTHS[index] * side
	local gone = math.clamp(math.round((1 - remaining) * 4 * side) - RUN_STARTS[index] * side, 0, length)
	local left = length - gone
	if index == 1 then
		return UDim2.fromOffset(side / 2 + gone, 0), UDim2.fromOffset(left, thickness)
	elseif index == 2 then
		return UDim2.fromOffset(side - thickness, gone), UDim2.fromOffset(thickness, left)
	elseif index == 3 then
		return UDim2.fromOffset(0, side - thickness), UDim2.fromOffset(left, thickness)
	elseif index == 4 then
		return UDim2.fromOffset(0, 0), UDim2.fromOffset(thickness, left)
	end
	return UDim2.fromOffset(gone, 0), UDim2.fromOffset(left, thickness)
end

local function remainingOf(status: EntityStore.Status, now: number): number
	local span = status.endsAt - status.startedAt
	if span <= 0 then
		return if now < status.endsAt then 1 else 0
	end
	return math.clamp((status.endsAt - now) / span, 0, 1)
end

local function trackEdge(color: Color3, size: UDim2, position: UDim2)
	return e("Frame", {
		Size = size,
		Position = position,
		BackgroundColor3 = color,
		BackgroundTransparency = MARK_TRACK_TRANSPARENCY,
		BorderSizePixel = 0,
	})
end

local function StatusMark(props: { status: EntityStore.Status, slot: number, clock: any })
	local theme = ThemeContext.useTheme()
	local status = props.status
	local look = StatusLooks.get(status.id)
	local ink = theme.color.textHeading
	local digits = Font.new(theme.face.mono.Family, Enum.FontWeight.Bold)

	local children: { [string]: any } = {
		Glyph = e(Glyph, {
			glyph = look.glyph,
			color = look.color,
			thickness = 1.5,
			size = UDim2.fromOffset(MARK_GLYPH, MARK_GLYPH),
		}),
		TrackTop = trackEdge(ink, UDim2.new(1, 0, 0, MARK_STROKE), UDim2.new()),
		TrackBottom = trackEdge(ink, UDim2.new(1, 0, 0, MARK_STROKE), UDim2.new(0, 0, 1, -MARK_STROKE)),
		TrackLeft = trackEdge(ink, UDim2.new(0, MARK_STROKE, 1, -2 * MARK_STROKE), UDim2.fromOffset(0, MARK_STROKE)),
		TrackRight = trackEdge(
			ink,
			UDim2.new(0, MARK_STROKE, 1, -2 * MARK_STROKE),
			UDim2.new(1, -MARK_STROKE, 0, MARK_STROKE)
		),
	}
	for index = 1, #RUN_STARTS do
		children[`Run{index}`] = e("Frame", {
			Position = props.clock:map(function(now: number)
				local position = outlineRun(index, remainingOf(status, now))
				return position
			end),
			Size = props.clock:map(function(now: number)
				local _, size = outlineRun(index, remainingOf(status, now))
				return size
			end),
			BackgroundColor3 = ink,
			BorderSizePixel = 0,
			ZIndex = 2,
		})
	end
	if status.stacks > 1 then
		children.Stacks = e("TextLabel", {
			Text = tostring(status.stacks),
			Size = UDim2.fromOffset(14, 14),
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, 0, 1, STACKS_OVERHANG),
			BackgroundTransparency = 1,
			FontFace = digits,
			TextSize = theme.type.small,
			TextColor3 = ink,
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 3,
		}, {
			Outline = e("UIStroke", { Color = theme.color.surface, Thickness = 2, Transparency = 0 }),
		})
	end
	if SHOW_SECONDS then
		children.Seconds = e("TextLabel", {
			Text = props.clock:map(function(now: number)
				local left = math.max(0, status.endsAt - now)
				return if left < 10 then string.format("%.1f", left) else tostring(math.floor(left))
			end),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			FontFace = digits,
			TextSize = theme.type.small,
			TextColor3 = ink,
			ZIndex = 3,
		}, {
			Outline = e("UIStroke", { Color = theme.color.surface, Thickness = 2, Transparency = 0 }),
		})
	end

	return e("Frame", {
		Size = UDim2.fromOffset(MARK, MARK),
		Position = UDim2.fromOffset((props.slot - 1) * (MARK + MARK_GAP), SIZE.Y + MARK_TOP),
		BackgroundColor3 = theme.color.surface,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
	}, children)
end

-- The marks in the order their effects arrived, so one does not jump along the row when another is
-- refreshed or ends.
local function useMarkOrder(statuses: { EntityStore.Status }): { EntityStore.Status }
	local arrival = React.useRef({ next = 0, order = {} :: { [string]: number } })
	local book = arrival.current :: { next: number, order: { [string]: number } }
	local shown: { EntityStore.Status } = {}
	local present: { [string]: true } = {}
	for _, status in ipairs(statuses) do
		if not StatusLooks.get(status.id).hidden then
			present[status.id] = true
			if not book.order[status.id] then
				book.next += 1
				book.order[status.id] = book.next
			end
			table.insert(shown, status)
		end
	end
	for id in pairs(book.order) do
		if not present[id] then
			book.order[id] = nil
		end
	end
	table.sort(shown, function(a, b)
		return book.order[a.id] < book.order[b.id]
	end)
	return shown
end

local function EnemyBar(props: { entry: EntityStore.Entry, placement: any, clock: any })
	local theme = ThemeContext.useTheme()
	local entry = props.entry
	local health = entry.health :: EntityStore.Health
	local value = if health.current and health.max
		then `{math.floor(health.current)}/{math.floor(health.max)}`
		else `{math.floor(health.ratio * 100 + 0.5)}%`

	local marks: { [string]: any } = {}
	for slot, status in ipairs(useMarkOrder(entry.statuses)) do
		if slot > MAX_MARKS then
			break
		end
		marks[`Status_{status.id}`] = e(StatusMark, { status = status, slot = slot, clock = props.clock })
	end

	return e("CanvasGroup", {
		Size = UDim2.fromOffset(FRAME.X, FRAME.Y),
		AnchorPoint = Vector2.new(0.5, SIZE.Y / FRAME.Y),
		Position = props.placement:map(function(p: Placement?)
			return if p then UDim2.fromOffset(p.position.X, p.position.Y) else UDim2.new()
		end),
		GroupTransparency = props.placement:map(function(p: Placement?)
			return if p then 1 - p.alpha else 1
		end),
		Visible = props.placement:map(function(p: Placement?)
			return p ~= nil and p.alpha > 0.01
		end),
		BackgroundTransparency = 1,
	}, {
		Name = e("TextLabel", {
			Text = entry.name,
			Size = UDim2.new(1, -70, 0, 20),
			BackgroundTransparency = 1,
			FontFace = theme.face.bodyBold,
			TextSize = theme.type.title,
			TextColor3 = theme.color.textHeading,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, {
			Outline = e("UIStroke", { Color = theme.color.surface, Thickness = 2, Transparency = 0 }),
		}),
		Value = e("TextLabel", {
			Text = value,
			Size = UDim2.new(0, 70, 0, 20),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			BackgroundTransparency = 1,
			FontFace = Font.new(theme.face.mono.Family, Enum.FontWeight.Bold),
			TextSize = theme.type.body,
			TextColor3 = theme.color.textPrimary,
			TextXAlignment = Enum.TextXAlignment.Right,
		}, {
			Outline = e("UIStroke", { Color = theme.color.surface, Thickness = 2, Transparency = 0 }),
		}),
		Gauge = e(SegmentedGauge, {
			value = health.ratio,
			color = theme.color.danger,
			segments = 16,
			trail = true,
			size = UDim2.new(1, 0, 0, 7),
			position = UDim2.fromOffset(0, SIZE.Y - 8),
		}),
		Marks = e(React.Fragment, nil, marks),
	})
end

local function EnemyBars()
	local entries = useEnemyHealth()
	local menu = useMenuState()
	local overlayOpen = useOverlayOpen()
	local shown = not menu.modal.open and not overlayOpen

	local layout, setLayout = React.useBinding({} :: { [string]: Placement })
	local clock, setClock = React.useBinding(Clock.serverNow())
	local current = React.useRef(entries)
	current.current = entries
	local visible = React.useRef(shown)
	visible.current = shown

	React.useEffect(function()
		local alphas: { [string]: number } = {}
		-- Where each bar last stood, so one losing its enemy fades out in place rather than vanishing.
		local lastScreen: { [string]: Vector2 } = {}
		local name = `EnemyBars_{HttpService:GenerateGUID(false)}`
		RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 1, function(dt: number)
			local camera = workspace.CurrentCamera
			if not camera then
				return
			end
			local viewport = camera.ViewportSize
			setClock(Clock.serverNow())

			-- Projected positions, and distance order for stepping down the far ones.
			local candidates: { { id: string, screen: Vector2, distance: number } } = {}
			local targets: { [string]: number } = {}
			local now = os.clock()
			for _, entry in ipairs(current.current :: { EntityStore.Entry }) do
				local anchor = entry.anchor
				targets[entry.id] = 0
				if anchor and anchor.Parent and entry.present and visible.current then
					local world = anchor.Position + Vector3.new(0, HEIGHT, 0)
					local point = camera:WorldToViewportPoint(world)
					local onScreen = point.Z > 0
						and point.X > -FRAME.X
						and point.X < viewport.X + FRAME.X
						and point.Y > -FRAME.Y
						and point.Y < viewport.Y + FRAME.Y
					if onScreen then
						table.insert(candidates, {
							id = entry.id,
							screen = Vector2.new(math.round(point.X) + joltOffset(entry.id, now), math.round(point.Y)),
							distance = (camera.CFrame.Position - world).Magnitude,
						})
					end
				end
			end
			table.sort(candidates, function(a, b)
				return a.distance < b.distance
			end)

			local out: { [string]: Placement } = {}
			for rank, candidate in ipairs(candidates) do
				local over = rank - FULL_COUNT
				targets[candidate.id] = if over > 0 then math.max(MIN_STRENGTH, 1 - over * 0.1) else 1
				out[candidate.id] = { position = candidate.screen, alpha = 0 }
				lastScreen[candidate.id] = candidate.screen
			end

			for id, target in pairs(targets) do
				local alpha = alphas[id] or 0
				local step = ALPHA_RATE * dt
				alpha = if alpha < target then math.min(target, alpha + step) else math.max(target, alpha - step)
				alphas[id] = alpha
				local placed = out[id]
				if placed then
					placed.alpha = alpha
				elseif alpha > 0 and lastScreen[id] then
					out[id] = { position = lastScreen[id], alpha = alpha }
				end
			end
			for id in pairs(alphas) do
				if targets[id] == nil then
					alphas[id] = nil
					lastScreen[id] = nil
				end
			end
			setLayout(out)
		end)
		return function()
			RunService:UnbindFromRenderStep(name)
		end
	end, {})

	local bars: { [string]: any } = {}
	for _, entry in ipairs(entries) do
		bars[entry.id] = e(EnemyBar, {
			entry = entry,
			clock = clock,
			placement = layout:map(function(all: { [string]: Placement })
				return all[entry.id]
			end),
		})
	end
	return e(React.Fragment, nil, bars)
end

return EnemyBars
