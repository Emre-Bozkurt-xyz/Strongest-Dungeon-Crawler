--!strict
-- The crosshair: where attacks go, and what they are about to do.
--
-- A dot and four ticks at the centre of the screen, where the camera aims (AimResolver). On it:
--   * the target: the ticks close in and turn the danger colour while attacks are going to an enemy
--     within the basic attack's reach, and dim while it is out of reach;
--   * brackets over that enemy in the world, faint for the soft target and solid for a lock
--     (TargetAssist);
--   * hit markers from the server's own hits: a cross for a hit, heavier and in the crit colour for a
--     critical, larger and in the danger colour for a kill;
--   * pips under it for the basic attack's combo while a chain is running;
--   * a ring of segments filling while a held skill charges (CombatSignals);
--   * a jolt in the danger colour when an attack is refused for want of resources.
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

-- Pixels.
local DOT = 4
local TICK_LENGTH = 7
local TICK_THICKNESS = 2
-- Ticks' distance from the centre: open, and closed on a target.
local GAP_OPEN = 9
local GAP_TARGET = 5
local HIT_GAP = 7
local HIT_LENGTH = { hit = 7, crit = 10, kill = 13 }
local HIT_DURATION = { hit = 0.18, crit = 0.26, kill = 0.45 }
local PIP = 5
local PIP_SPACING = 9
local PIPS_Y = 20
local RING_RADIUS = 21
local RING_SEGMENTS = 24
local RING_DOT = 3
-- Projected height of the bracket box over a target, in studs.
local BRACKET_STUDS = 5.5
local BRACKET_MIN = 28
local REFUSED_DURATION = 0.28
local REFUSED_SHAKE = 4
-- Studs added to a melee cone's reach: it is measured to the target's centre, which sits inside it.
local MELEE_MARGIN = 1.5
-- How long after a hit the target is checked for having died of it.
local KILL_CHECK = 0.3
-- The basic attack's skill, whose combo the pips follow.
local BASIC_ATTACK = "BasicAttack"

type HitKind = "hit" | "crit" | "kill"

-- How far the basic attack reaches with what is held: a shot's flight, or a swing's cone.
local function reachOf(combat: ItemTypes.CombatLoadoutSnapshot?): number
	local profile = BasicAttackProfileRegistry.resolve(combat)
	local projectile = combat and combat.main and combat.main.projectile
	if projectile and BasicAttackProfileRegistry.hasProjectileStep(profile) then
		return projectile.launchSpeed * projectile.lifetime
	end
	return profile.hitCone.range + MELEE_MARGIN
end

local function line(parent: Instance, color: Color3, outline: Color3): Frame
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	-- A dark edge, so the mark reads over a bright sky as well as a dark floor.
	local stroke = Instance.new("UIStroke")
	stroke.Color = outline
	stroke.Transparency = 0.45
	stroke.Thickness = 1
	stroke.Parent = frame
	frame.Parent = parent
	return frame
end

local function corners(parent: Instance, color: Color3, length: number, thickness: number): { Frame }
	local pieces: { Frame } = {}
	for _, corner in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
		for _, horizontal in ipairs({ true, false }) do
			local piece = Instance.new("Frame")
			piece.AnchorPoint = Vector2.new(corner[1], corner[2])
			piece.Position = UDim2.fromScale(corner[1], corner[2])
			piece.Size = if horizontal
				then UDim2.fromOffset(length, thickness)
				else UDim2.fromOffset(thickness, length)
			piece.BackgroundColor3 = color
			piece.BorderSizePixel = 0
			piece.Parent = parent
			table.insert(pieces, piece)
		end
	end
	return pieces
end

local function build(root: Frame, theme: any): () -> ()
	local colors = theme.color
	local outline = colors.surface

	local centre = Instance.new("Frame")
	centre.Name = "Reticle"
	centre.BackgroundTransparency = 1
	centre.Size = UDim2.fromOffset(0, 0)
	centre.Parent = root

	local dot = line(centre, colors.textPrimary, outline)
	dot.Size = UDim2.fromOffset(DOT, DOT)

	-- Up, right, down, left.
	local directions = { Vector2.new(0, -1), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(-1, 0) }
	local ticks: { Frame } = {}
	for index, direction in ipairs(directions) do
		local tick = line(centre, colors.textPrimary, outline)
		tick.Size = if direction.X ~= 0
			then UDim2.fromOffset(TICK_LENGTH, TICK_THICKNESS)
			else UDim2.fromOffset(TICK_THICKNESS, TICK_LENGTH)
		ticks[index] = tick
	end

	-- The hit marker: four strokes on the diagonals.
	local diagonals = { Vector2.new(-1, -1), Vector2.new(1, -1), Vector2.new(1, 1), Vector2.new(-1, 1) }
	local hitStrokes: { Frame } = {}
	for index, direction in ipairs(diagonals) do
		local stroke = line(centre, colors.textPrimary, outline)
		stroke.Rotation = if direction.X * direction.Y > 0 then 45 else -45
		stroke.Visible = false
		hitStrokes[index] = stroke
	end

	local pips: { Frame } = {}
	local ring: { Frame } = {}
	for index = 1, RING_SEGMENTS do
		local angle = (index - 1) / RING_SEGMENTS * math.pi * 2
		local segment = line(centre, colors.accent, outline)
		segment.Size = UDim2.fromOffset(RING_DOT, RING_DOT)
		segment.Position = UDim2.fromOffset(math.sin(angle) * RING_RADIUS, -math.cos(angle) * RING_RADIUS)
		segment.Visible = false
		ring[index] = segment
	end

	local function bracketBox(name: string, color: Color3, length: number, thickness: number): Frame
		local box = Instance.new("Frame")
		box.Name = name
		box.AnchorPoint = Vector2.new(0.5, 0.5)
		box.BackgroundTransparency = 1
		box.Visible = false
		box.Parent = root
		corners(box, color, length, thickness)
		return box
	end
	local lockBox = bracketBox("Lock", colors.accent, 10, 2)
	local softBox = bracketBox("Soft", colors.textMuted, 7, 2)

	-- Hits from the server: only the player's own.
	local hit: { kind: HitKind, at: number }? = nil
	local function mark(kind: HitKind)
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
		mark(if result.crit then "crit" else "hit")
		local targetId = event.targetId
		task.delay(KILL_CHECK, function()
			if type(targetId) == "string" and not EntityStore.isAlive(targetId) then
				mark("kill")
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

	local function placeBox(box: Frame, camera: Camera, anchor: BasePart?)
		if not anchor or not anchor.Parent then
			box.Visible = false
			return
		end
		local position = anchor.Position
		local top, topOnScreen = camera:WorldToViewportPoint(position + Vector3.new(0, BRACKET_STUDS / 2, 0))
		local bottom, bottomOnScreen = camera:WorldToViewportPoint(position - Vector3.new(0, BRACKET_STUDS / 2, 0))
		if not topOnScreen and not bottomOnScreen then
			box.Visible = false
			return
		end
		local height = math.max(math.abs(bottom.Y - top.Y), BRACKET_MIN)
		box.Visible = true
		box.Position = UDim2.fromOffset((top.X + bottom.X) / 2, (top.Y + bottom.Y) / 2)
		box.Size = UDim2.fromOffset(height * 0.75, height)
	end

	local connection = RunService.RenderStepped:Connect(function()
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
		centre.Position = UDim2.fromOffset(viewport.X / 2 + shake, viewport.Y / 2)

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

		local color = if refused
			then colors.danger
			elseif target and inReach then colors.danger
			elseif target then colors.textMuted
			else colors.textPrimary
		local gap = if target and inReach then GAP_TARGET else GAP_OPEN
		local transparency = if target and not inReach then 0.35 else 0.05
		dot.BackgroundColor3 = color
		dot.BackgroundTransparency = transparency
		for index, tick in ipairs(ticks) do
			local direction = directions[index]
			local offset = gap + TICK_LENGTH / 2
			tick.Position = UDim2.fromOffset(direction.X * offset, direction.Y * offset)
			tick.BackgroundColor3 = color
			tick.BackgroundTransparency = transparency
		end

		placeBox(lockBox, camera, if targeting.locked then targeting.locked.anchor else nil)
		placeBox(softBox, camera, if targeting.soft then targeting.soft.anchor else nil)

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
				stroke.Size = UDim2.fromOffset(length, if current.kind == "hit" then 2 else 3)
				stroke.Position = UDim2.fromOffset(direction.X * offset * 0.7071, direction.Y * offset * 0.7071)
				stroke.BackgroundColor3 = if current.kind == "kill"
					then colors.danger
					elseif current.kind == "crit" then colors.critical
					else colors.textPrimary
				stroke.BackgroundTransparency = fade * fade
			end
		end

		-- Combo pips: one per step, lit up to the step just played, while the chain can continue.
		local combo = SkillPacer.getComboState(BASIC_ATTACK)
		local total = if combo and combo.totalSteps > 1 and now < combo.chainEndsAt then combo.totalSteps else 0
		for index = 1, math.max(total, #pips) do
			local pip = pips[index]
			if index <= total then
				if not pip then
					pip = line(centre, colors.textPrimary, outline)
					pip.Size = UDim2.fromOffset(PIP, PIP)
					pips[index] = pip
				end
				pip.Visible = true
				pip.Position = UDim2.fromOffset((index - (total + 1) / 2) * PIP_SPACING, PIPS_Y)
				pip.BackgroundTransparency = if combo and index <= combo.currentStep then 0.05 else 0.7
			elseif pip then
				pip.Visible = false
			end
		end

		-- Charge ring: segments light clockwise from the top as the charge fills.
		local cast = CombatSignals.getCast()
		local filled = if cast then math.clamp((now - cast.startedAt) / cast.duration, 0, 1) else 0
		local lit = math.floor(filled * RING_SEGMENTS + 0.5)
		for index, segment in ipairs(ring) do
			segment.Visible = cast ~= nil
			segment.BackgroundTransparency = if index <= lit then 0 else 0.75
			segment.BackgroundColor3 = if filled >= 1 then colors.textPrimary else colors.accent
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
