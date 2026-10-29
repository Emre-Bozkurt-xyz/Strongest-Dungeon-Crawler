--!strict
-- The crosshair: where attacks go, and what they are about to do.
--
-- A dot and four short strokes at the centre of the screen, where the camera aims (AimResolver),
-- in a pale ink that runs from a cool to a warm white so it never reads as flat white. On it:
--   * the target: the strokes close in while attacks are going to an enemy within the basic
--     attack's reach, and dim while it is out of reach;
--   * corners over that enemy in the world, faint for the soft target and full for a lock, which
--     close in on the enemy as it is locked (TargetAssist);
--   * hit markers from the server's own hits: a cross for a hit, longer and gold for a critical,
--     longest and red for a kill;
--   * dashes under it for the basic attack's combo, lit up to the step just played; after the last
--     step they empty over its end lag, so the chain is seen to reset before the next one starts;
--   * a tall thin arc to its right while a held skill charges (CombatSignals): a line filling from
--     the bottom for a smooth charge such as a draw, or one bead per thing gathered (mana balls),
--     empty at first and filling in the charge's colour;
--   * a short shake and a red flash when an attack is refused for want of resources.
--
-- Under a lock the target's corners become the crosshair: the dot and strokes fade out, the corners
-- dim and flash as the strokes would, and the hit markers, combo dashes and charge arc glide over to
-- the target, standing off its corners, and back when the lock ends.
--
-- Shown only while the cursor is captured for aiming. It changes every frame, so its pieces are
-- built once and updated in place rather than re-rendered through React.
--
-- `script` here IS the Crosshair module (init.luau collapses into its folder), so Parent is
-- `panels` and Parent.Parent is `ui`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local React = require(ReplicatedStorage.Packages.React)
local Networking = require(ReplicatedStorage.Shared.Networking)
local BasicAttackProfileRegistry = require(ReplicatedStorage.Shared.skills.BasicAttackProfileRegistry)
local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)

local ThemeContext = require(script.Parent.Parent.hooks.ThemeContext)
local TargetAssist = require(script.Parent.Parent.Parent.SkillsFramework.TargetAssist)
local CombatSignals = require(script.Parent.Parent.Parent.SkillsFramework.CombatSignals)
local SkillPacer = require(script.Parent.Parent.Parent.SkillsFramework.SkillPacer)
local CombatLoadoutMirror = require(script.Parent.Parent.Parent.Inventory.CombatLoadoutMirror)
local EntityStore = require(script.Parent.Parent.Parent.Entities.EntityStore)
local Registrar = require(script.Parent.Parent.Parent.Services.Registrar)

local e = React.createElement

-- The ink: a white leaning blue at one end and yellow at the other.
local INK_COOL = Color3.fromRGB(222, 236, 255)
local INK_WARM = Color3.fromRGB(255, 246, 222)
-- A soft dark edge under every mark, so it reads over a bright sky as well as a dark floor.
local SHADE = Color3.fromRGB(6, 10, 18)
local SHADE_TRANSPARENCY = 0.62

-- Pixels.
local DOT = 3
local STROKE_LENGTH = 6
local STROKE_THICKNESS = 2
-- Strokes' distance from the centre: open, and closed on a target in reach.
local GAP_OPEN = 8
local GAP_TARGET = 4
local CLOSE_RATE = 18
local HIT_GAP = 6
local HIT_LENGTH = { hit = 6, crit = 9, kill = 12 }
local HIT_DURATION = { hit = 0.18, crit = 0.26, kill = 0.45 }
local DASH_LENGTH = 9
local DASH_SPACING = 13
local DASHES_Y = 19
-- Empty dashes stay up this long after a chain ends before fading, so the reset is seen.
local DASHES_LINGER = 0.35
local DASHES_FADE = 0.2
-- The charge arc: part of a circle around the centre, on its right.
local ARC_RADIUS = 58
local ARC_SPAN = math.rad(42)
local ARC_THICKNESS = 2
local BEAD = 7
local MAX_BEADS = 6
-- Corners over a target in the world: a square around the enemy's model, as wide as its larger
-- side and a little more, so a slime and a giant are each framed and not one shape stretched over
-- both. An enemy whose model measures badly (a long tail, a staff held high) sets a `TargetFrame`
-- attribute on its model, the square's side in studs.
local FRAME_ATTRIBUTE = "TargetFrame"
local FRAME_PADDING = 1.15
local FRAME_FALLBACK = 5
local BRACKET_MIN = 28
local LOCK_CORNER = 13
local SOFT_CORNER = 6
local LOCK_SNAP = 0.16
local LOCK_SNAP_SCALE = 1.45
-- Seconds for the crosshair's pieces to move onto a locked target, or back.
local LOCK_MOVE = 0.18
-- Pixels between a locked target's corners and the charge arc beside them.
local ARC_CLEARANCE = 12
local REFUSED_DURATION = 0.28
local REFUSED_SHAKE = 4
-- Studs added to a melee cone's reach: it is measured to the target's centre, which sits inside it.
local MELEE_MARGIN = 1.5
-- How long after a hit the target is checked for having died of it.
local KILL_CHECK = 0.3
-- The basic attack's skill, whose combo the dashes follow.
local BASIC_ATTACK = "BasicAttack"

type HitKind = "hit" | "crit" | "kill"

local INK_SEQUENCE = ColorSequence.new(INK_COOL, INK_WARM)

-- How far the basic attack reaches with what is held: a shot's flight, or a swing's cone.
local function reachOf(combat: ItemTypes.CombatLoadoutSnapshot?): number
	local profile = BasicAttackProfileRegistry.resolve(combat)
	local projectile = combat and combat.main and combat.main.projectile
	if projectile and BasicAttackProfileRegistry.hasProjectileStep(profile) then
		return projectile.launchSpeed * projectile.lifetime
	end
	return profile.hitCone.range + MELEE_MARGIN
end

local function lighten(color: Color3, amount: number): Color3
	return color:Lerp(Color3.new(1, 1, 1), amount)
end

-- A rounded mark in the ink, with its shade.
local function mark(parent: Instance, width: number, height: number): Frame
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Size = UDim2.fromOffset(width, height)
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = frame
	local gradient = Instance.new("UIGradient")
	gradient.Color = INK_SEQUENCE
	gradient.Rotation = 45
	gradient.Parent = frame
	local shade = Instance.new("UIStroke")
	shade.Color = SHADE
	shade.Transparency = SHADE_TRANSPARENCY
	shade.Thickness = 1
	shade.Parent = frame
	frame.Parent = parent
	return frame
end

local function setAlpha(frame: Frame, transparency: number)
	frame.BackgroundTransparency = transparency
	local shade = frame:FindFirstChildOfClass("UIStroke")
	if shade then
		shade.Transparency = SHADE_TRANSPARENCY + (1 - SHADE_TRANSPARENCY) * transparency
	end
end

local function corners(parent: Instance, length: number): { Frame }
	local pieces: { Frame } = {}
	for _, corner in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
		for _, horizontal in ipairs({ true, false }) do
			local piece = mark(
				parent,
				if horizontal then length else STROKE_THICKNESS,
				if horizontal then STROKE_THICKNESS else length
			)
			piece.AnchorPoint = Vector2.new(corner[1], corner[2])
			piece.Position = UDim2.fromScale(corner[1], corner[2])
			-- Square ends, so the two strokes meet in a clean corner.
			local rounding = piece:FindFirstChildOfClass("UICorner")
			if rounding then
				rounding:Destroy()
			end
			table.insert(pieces, piece)
		end
	end
	return pieces
end

-- A ring around the centre whose stroke shows only through `clip`, which crops it to the arc.
local function ring(clip: Frame, origin: Vector2, radius: number, thickness: number, color: Color3): (UIStroke, UIGradient)
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromOffset(origin.X, origin.Y)
	frame.Size = UDim2.fromOffset(radius * 2, radius * 2)
	frame.BackgroundTransparency = 1
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Parent = frame
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = -90
	gradient.Parent = stroke
	frame.Parent = clip
	return stroke, gradient
end

-- A point on the arc, `angle` up from its middle, relative to the centre.
local function onArc(angle: number): Vector2
	local radius = ARC_RADIUS + ARC_THICKNESS / 2
	return Vector2.new(math.cos(angle) * radius, -math.sin(angle) * radius)
end

local function build(root: Frame, theme: any): () -> ()
	local colors = theme.color
	local hitColor: { [HitKind]: Color3 } = {
		hit = Color3.new(1, 1, 1),
		crit = lighten(colors.critical, 0.25),
		kill = lighten(colors.danger, 0.2),
	}
	local refusedColor = lighten(colors.danger, 0.2)
	local resourceColor: { [string]: Color3 } = {
		Mana = lighten(theme.rarity.magic, 0.45),
	}

	local centre = Instance.new("Frame")
	centre.Name = "Reticle"
	centre.BackgroundTransparency = 1
	centre.Size = UDim2.fromOffset(0, 0)
	centre.Parent = root

	local dot = mark(centre, DOT, DOT)

	-- Up, right, down, left.
	local directions = { Vector2.new(0, -1), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(-1, 0) }
	local strokes: { Frame } = {}
	for index, direction in ipairs(directions) do
		strokes[index] = if direction.X ~= 0
			then mark(centre, STROKE_LENGTH, STROKE_THICKNESS)
			else mark(centre, STROKE_THICKNESS, STROKE_LENGTH)
	end

	-- The hit marker: four strokes on the diagonals.
	local diagonals = { Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(1, 1), Vector2.new(-1, 1) }
	local hitStrokes: { Frame } = {}
	for index, direction in ipairs(diagonals) do
		local stroke = mark(centre, HIT_LENGTH.hit, STROKE_THICKNESS)
		stroke.Rotation = if direction.X * direction.Y > 0 then 45 else -45
		stroke.Visible = false
		hitStrokes[index] = stroke
	end

	-- Under a lock these two groups stand off the target's corners instead of the centre's.
	local dashGroup = Instance.new("Frame")
	dashGroup.Name = "Combo"
	dashGroup.BackgroundTransparency = 1
	dashGroup.Size = UDim2.fromOffset(0, 0)
	dashGroup.Parent = centre
	local chargeGroup = dashGroup:Clone()
	chargeGroup.Name = "ChargeGroup"
	chargeGroup.Parent = centre

	local dashes: { Frame } = {}

	-- The charge arc, cropped from two rings: a faint track, and the fill over it.
	local arcLeft = math.cos(ARC_SPAN) * ARC_RADIUS
	local arcHalf = math.sin(ARC_SPAN) * (ARC_RADIUS + ARC_THICKNESS)
	local arc = Instance.new("Frame")
	arc.Name = "Charge"
	arc.BackgroundTransparency = 1
	arc.ClipsDescendants = true
	arc.Position = UDim2.fromOffset(arcLeft, -arcHalf)
	arc.Size = UDim2.fromOffset(ARC_RADIUS + ARC_THICKNESS * 2 + 2 - arcLeft, arcHalf * 2)
	arc.Visible = false
	arc.Parent = chargeGroup
	local origin = Vector2.new(-arcLeft, arcHalf)
	local shadeStroke, shadeGradient = ring(arc, origin, ARC_RADIUS - 1, ARC_THICKNESS + 2, SHADE)
	local trackStroke, trackGradient = ring(arc, origin, ARC_RADIUS, ARC_THICKNESS, Color3.new(1, 1, 1))
	local _, fillGradient = ring(arc, origin, ARC_RADIUS, ARC_THICKNESS, Color3.new(1, 1, 1))
	trackGradient.Color = INK_SEQUENCE
	fillGradient.Color = INK_SEQUENCE
	trackStroke.Transparency = 0.8
	shadeStroke.Transparency = SHADE_TRANSPARENCY + 0.15

	-- Beads, one per thing the charge gathers, along the arc from the bottom.
	local beads: { { ring: Frame, outline: UIStroke, fill: Frame } } = {}
	local function bead(index: number)
		local existing = beads[index]
		if existing then
			return existing
		end
		local holder = Instance.new("Frame")
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Size = UDim2.fromOffset(BEAD, BEAD)
		holder.BackgroundColor3 = SHADE
		holder.BackgroundTransparency = 0.8
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = holder
		local outline = Instance.new("UIStroke")
		outline.Thickness = 1
		outline.Parent = holder
		local fill = Instance.new("Frame")
		fill.AnchorPoint = Vector2.new(0.5, 0.5)
		fill.Position = UDim2.fromScale(0.5, 0.5)
		fill.BorderSizePixel = 0
		local fillCorner = Instance.new("UICorner")
		fillCorner.CornerRadius = UDim.new(1, 0)
		fillCorner.Parent = fill
		fill.Parent = holder
		holder.Parent = chargeGroup
		local made = { ring = holder, outline = outline, fill = fill }
		beads[index] = made
		return made
	end

	-- The fill ring's stroke as a bottom-up gradient: opaque below `filled` of the arc, clear above.
	-- The gradient spans the ring's whole box, so the arc's share of it is worked out from its angles.
	local function fillTo(gradient: UIGradient, filled: number)
		if filled <= 0 then
			gradient.Transparency = NumberSequence.new(1)
			return
		end
		local extent = ARC_RADIUS + ARC_THICKNESS
		local edge = onArc(-ARC_SPAN + filled * ARC_SPAN * 2)
		local at = math.clamp((extent - edge.Y) / (extent * 2), 0.002, 0.996)
		if filled >= 1 then
			at = 0.996
		end
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(at, 0),
			NumberSequenceKeypoint.new(at + 0.002, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
	end

	local function bracketBox(name: string, length: number): Frame
		local box = Instance.new("Frame")
		box.Name = name
		box.AnchorPoint = Vector2.new(0.5, 0.5)
		box.BackgroundTransparency = 1
		box.Visible = false
		box.Parent = root
		corners(box, length)
		return box
	end
	local lockBox = bracketBox("Lock", LOCK_CORNER)
	local softBox = bracketBox("Soft", SOFT_CORNER)
	for _, piece in ipairs(softBox:GetChildren()) do
		if piece:IsA("Frame") then
			setAlpha(piece, 0.55)
		end
	end

	-- Hits from the server: only the player's own.
	local hit: { kind: HitKind, at: number }? = nil
	local function markHit(kind: HitKind)
		local current = hit
		-- A kill outranks the hit that caused it; a later plain hit does not hide a kill or crit.
		if current and os.clock() - current.at < HIT_DURATION[current.kind] and HIT_LENGTH[current.kind] > HIT_LENGTH[kind] then
			return
		end
		hit = { kind = kind, at = os.clock() }
	end
	local offHit = (Networking.client() :: any):on("HitEvent", function(event)
		if type(event) ~= "table" or event.sourceId ~= Registrar.getLocalEntityId() then
			return
		end
		local result = event.result or {}
		if result.dodged or (result.totalDamage or 0) <= 0 then
			return
		end
		markHit(if result.crit then "crit" else "hit")
		local targetId = event.targetId
		task.delay(KILL_CHECK, function()
			if type(targetId) == "string" and not EntityStore.isAlive(targetId) then
				markHit("kill")
			end
		end)
	end)

	local refusedAt = -math.huge
	local offRefused = CombatSignals.onRejected(function(reason)
		if reason == "insufficient_resources" then
			refusedAt = os.clock()
		end
	end)

	local cachedCombat: ItemTypes.CombatLoadoutSnapshot? = nil
	local reach = reachOf(nil)
	local gap = GAP_OPEN
	local lockedAnchor: BasePart? = nil
	local lockedAt = 0
	-- The combo as the dashes last drew it: when its last step began and when it ends, for the
	-- emptying; and when the chain ended, for the linger.
	local finalStarted: number? = nil
	local chainEnded: number? = nil
	local lastTotal = 0

	-- Where a lock moved the crosshair's pieces to, and how far along that move they are: 0 at the
	-- centre of the screen, 1 on the target. Kept after the lock ends, to move back from.
	local lockBlend = 0
	local lockMiddle = Vector2.zero
	local lockHalf = Vector2.zero

	-- Each target's frame, measured once when it is first marked: the square's side, and its middle
	-- relative to the anchor. Measured once because the model's bounds move with every animation
	-- frame, and a frame breathing with the idle would read as noise.
	local frames: { [BasePart]: { side: number, offset: Vector3 } } = setmetatable({}, { __mode = "k" }) :: any
	local function frameOf(anchor: BasePart): { side: number, offset: Vector3 }
		local known = frames[anchor]
		if known then
			return known
		end
		local model = anchor:FindFirstAncestorOfClass("Model")
		local side = FRAME_FALLBACK
		local offset = Vector3.zero
		if model then
			local boxFrame, size = model:GetBoundingBox()
			side = math.max(size.Y, math.max(size.X, size.Z)) * FRAME_PADDING
			offset = boxFrame.Position - anchor.Position
			local authored = model:GetAttribute(FRAME_ATTRIBUTE)
			if type(authored) == "number" and authored > 0 then
				side = authored
			end
		end
		local made = { side = side, offset = offset }
		frames[anchor] = made
		return made
	end

	-- Puts `box` over `anchor`; returns the box's middle and, at `scale` 1, its size.
	local function placeBox(box: Frame, camera: Camera, anchor: BasePart?, scale: number, shake: number): (Vector2?, Vector2?)
		if not anchor or not anchor.Parent then
			box.Visible = false
			return nil, nil
		end
		local frame = frameOf(anchor)
		local position = anchor.Position + frame.offset
		local top, topOnScreen = camera:WorldToViewportPoint(position + Vector3.new(0, frame.side / 2, 0))
		local bottom, bottomOnScreen = camera:WorldToViewportPoint(position - Vector3.new(0, frame.side / 2, 0))
		if not topOnScreen and not bottomOnScreen then
			box.Visible = false
			return nil, nil
		end
		local side = math.max(math.abs(bottom.Y - top.Y), BRACKET_MIN)
		local middle = Vector2.new((top.X + bottom.X) / 2 + shake, (top.Y + bottom.Y) / 2)
		box.Visible = true
		box.Position = UDim2.fromOffset(middle.X, middle.Y)
		box.Size = UDim2.fromOffset(side * scale, side * scale)
		return middle, Vector2.new(side, side)
	end

	local connection = RunService.RenderStepped:Connect(function(dt)
		local camera = Workspace.CurrentCamera
		if not camera or not TargetAssist.isActive() then
			root.Visible = false
			return
		end
		root.Visible = true
		local now = os.clock()
		local viewport = camera.ViewportSize

		-- Refused: a short sideways shake.
		local refusedAge = now - refusedAt
		local refused = refusedAge < REFUSED_DURATION
		local shake = if refused
			then math.sin(refusedAge * 70) * REFUSED_SHAKE * (1 - refusedAge / REFUSED_DURATION)
			else 0

		local combat = CombatLoadoutMirror.get()
		if combat ~= cachedCombat then
			cachedCombat = combat
			reach = reachOf(combat)
		end

		local targeting = TargetAssist.get()
		local target = TargetAssist.current()
		local inReach = false
		if target then
			local character = Registrar.getLocalPlayerEntity()
			local myRoot = character and character:FindFirstChild("HumanoidRootPart")
			inReach = myRoot ~= nil
				and myRoot:IsA("BasePart")
				and (target.anchor.Position - myRoot.Position).Magnitude <= reach
		end

		local tint = if refused then refusedColor else Color3.new(1, 1, 1)
		local transparency = if target and not inReach then 0.45 else 0

		-- The lock's corners start wide and close onto the enemy as it is taken.
		local locked = if targeting.locked then targeting.locked.anchor else nil
		if locked ~= lockedAnchor then
			lockedAnchor = locked
			lockedAt = now
		end
		local snap = math.clamp((now - lockedAt) / LOCK_SNAP, 0, 1)
		local eased = 1 - (1 - snap) * (1 - snap)
		local middle, size = placeBox(lockBox, camera, locked, LOCK_SNAP_SCALE + (1 - LOCK_SNAP_SCALE) * eased, shake)
		-- Under a lock the soft target is not where attacks go, so it is not marked.
		placeBox(softBox, camera, if targeting.soft and not locked then targeting.soft.anchor else nil, 1, 0)
		for _, piece in ipairs(lockBox:GetChildren()) do
			if piece:IsA("Frame") then
				piece.BackgroundColor3 = tint
				setAlpha(piece, transparency)
			end
		end

		-- Under a lock the corners are the crosshair: the dot and strokes fade, and everything else
		-- the crosshair shows moves to the target, standing off its corners.
		if middle and size then
			lockMiddle = middle
			lockHalf = size / 2
		end
		local blendGoal = if middle then 1 else 0
		lockBlend = math.clamp(lockBlend + math.sign(blendGoal - lockBlend) * dt / LOCK_MOVE, 0, 1)
		local blend = lockBlend * lockBlend * (3 - 2 * lockBlend)
		local screenMiddle = Vector2.new(viewport.X / 2 + shake, viewport.Y / 2)
		local point = screenMiddle:Lerp(lockMiddle, blend)
		centre.Position = UDim2.fromOffset(math.floor(point.X), math.floor(point.Y))
		local half = lockHalf * blend
		dashGroup.Position = UDim2.fromOffset(0, math.round(half.Y))
		chargeGroup.Position = UDim2.fromOffset(math.round(math.max(half.X + ARC_CLEARANCE - arcLeft, 0)), 0)

		local goal = if target and inReach then GAP_TARGET else GAP_OPEN
		gap += (goal - gap) * math.min(dt * CLOSE_RATE, 1)
		local reticleTransparency = 1 - (1 - transparency) * (1 - blend)
		dot.BackgroundColor3 = tint
		setAlpha(dot, reticleTransparency)
		for index, stroke in ipairs(strokes) do
			local direction = directions[index]
			local offset = gap + STROKE_LENGTH / 2
			stroke.Position = UDim2.fromOffset(math.round(direction.X * offset), math.round(direction.Y * offset))
			stroke.BackgroundColor3 = tint
			setAlpha(stroke, reticleTransparency)
		end

		-- Hit marker, fading out over its duration.
		local current = hit
		local hitAge = if current then now - current.at else math.huge
		local showing = current ~= nil and hitAge < HIT_DURATION[current.kind]
		for index, stroke in ipairs(hitStrokes) do
			stroke.Visible = showing
			if showing and current then
				local length = HIT_LENGTH[current.kind]
				local fade = hitAge / HIT_DURATION[current.kind]
				local direction = diagonals[index]
				local offset = HIT_GAP + length / 2 + fade * 3
				stroke.Size = UDim2.fromOffset(length, STROKE_THICKNESS)
				stroke.Position = UDim2.fromOffset(direction.X * offset * 0.7071, direction.Y * offset * 0.7071)
				stroke.BackgroundColor3 = hitColor[current.kind]
				setAlpha(stroke, fade * fade)
			end
		end

		-- Combo dashes. Lit up to the step just played while the chain can go on; after its last
		-- step, all lit and emptying until the chain is over; then empty for a moment, and gone.
		local combo = SkillPacer.getComboState(BASIC_ATTACK)
		local total = 0
		local lit = 0
		local dim = 0
		if combo and combo.totalSteps > 1 and now < combo.chainEndsAt then
			total = combo.totalSteps
			lastTotal = total
			chainEnded = nil
			if combo.currentStep >= total then
				local started = finalStarted or now
				finalStarted = started
				lit = total
				dim = math.clamp((now - started) / math.max(combo.chainEndsAt - started, 0.05), 0, 1)
			else
				finalStarted = nil
				lit = combo.currentStep
			end
		else
			finalStarted = nil
			if lastTotal > 0 then
				local ended = chainEnded or now
				chainEnded = ended
				local age = now - ended
				if age < DASHES_LINGER + DASHES_FADE then
					total = lastTotal
					dim = 1
				else
					lastTotal = 0
					chainEnded = nil
				end
			end
		end
		local fadeOut = if chainEnded then math.clamp((now - chainEnded - DASHES_LINGER) / DASHES_FADE, 0, 1) else 0
		for index = 1, math.max(total, #dashes) do
			local dash = dashes[index]
			if index <= total then
				if not dash then
					dash = mark(dashGroup, DASH_LENGTH, STROKE_THICKNESS)
					dashes[index] = dash
				end
				dash.Visible = true
				dash.Position =
					UDim2.fromOffset(math.round((index - (total + 1) / 2) * DASH_SPACING), DASHES_Y)
				local on = if index <= lit then 1 - dim else 0
				local alpha = 0.78 - 0.78 * on
				setAlpha(dash, alpha + (1 - alpha) * fadeOut)
			elseif dash then
				dash.Visible = false
			end
		end

		-- The charge arc.
		local cast = CombatSignals.getCast()
		arc.Visible = cast ~= nil
		local beadCount = 0
		if cast then
			local filled = math.clamp((now - cast.startedAt) / cast.duration, 0, 1)
			local beadColor = (cast.resource and resourceColor[cast.resource]) or Color3.new(1, 1, 1)
			if cast.charges and cast.charges > 0 then
				-- Too many to draw one each (thirty mana balls) and each bead stands for a share.
				beadCount = math.min(cast.charges, MAX_BEADS)
				fillTo(fillGradient, 0)
				fillTo(shadeGradient, 0)
				for index = 1, beadCount do
					local made = bead(index)
					local share = math.clamp(filled * beadCount - (index - 1), 0, 1)
					local at = onArc(-ARC_SPAN + (index - 0.5) / beadCount * ARC_SPAN * 2)
					made.ring.Visible = true
					made.ring.Position = UDim2.fromOffset(math.round(at.X), math.round(at.Y))
					made.fill.BackgroundColor3 = beadColor
					made.fill.Size = UDim2.fromScale(share, share)
					made.fill.Visible = share > 0
					made.outline.Color = if share >= 1 then beadColor else INK_COOL
					made.outline.Transparency = if share >= 1 then 0 else 0.3
				end
			else
				fillTo(fillGradient, filled)
				fillTo(shadeGradient, filled)
			end
			trackStroke.Transparency = if filled >= 1 then 0.6 else 0.8
		end
		for index = beadCount + 1, #beads do
			beads[index].ring.Visible = false
		end
	end)

	return function()
		connection:Disconnect()
		offHit()
		offRefused()
		centre:Destroy()
		lockBox:Destroy()
		softBox:Destroy()
	end
end

local function Crosshair()
	local theme = ThemeContext.useTheme()
	local rootRef = React.useRef(nil :: Frame?)

	React.useEffect(function()
		local root = rootRef.current
		if not root then
			return nil
		end
		return build(root, theme)
	end, { theme })

	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		ref = rootRef,
	})
end

return Crosshair
