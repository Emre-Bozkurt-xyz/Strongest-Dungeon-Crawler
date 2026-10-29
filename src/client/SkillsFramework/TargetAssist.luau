--!strict
-- TargetAssist: which enemy the player's attacks go to.
--
-- Two layers, both meant to help and never to take the character away from the player:
--   * The soft target, always on: the enemy nearest the crosshair, within a small circle of it, in
--     range and in sight. Attacks bend toward it -- the character turns to it for the swing and a
--     shot is aimed at it -- and nothing else changes. Camera and movement stay the player's.
--   * The lock (middle mouse): keeps one enemy as the target even when it is off-centre. The camera
--     leaves it alone while it stays in the middle of the view, and turns only as far as it takes to
--     bring it back to the edge of that zone once it leaves. The mouse still looks around: a quick
--     flick sideways switches to the nearest enemy that way, and dragging the target well out of
--     view lets it go. It also lets go when the target dies, gets out of range or stays out of sight.
--
-- The character turns to the target only while it attacks, so moving under a lock is still moving
-- where the camera points, not backpedalling around the target.
--
-- Only in the over-the-shoulder camera with the cursor captured: with a free cursor the player is
-- pointing at things, not aiming.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local EntityUtils = require(ReplicatedStorage.Shared.EntityUtils)
local BasicAttackProfileRegistry = require(ReplicatedStorage.Shared.skills.BasicAttackProfileRegistry)

local EntityStore = require(script.Parent.Parent.Entities.EntityStore)
local Registrar = require(script.Parent.Parent.Services.Registrar)
local CombatLoadoutMirror = require(script.Parent.Parent.Inventory.CombatLoadoutMirror)
local CameraController = require(script.Parent.Parent.CameraController)
local CharacterFacingController = require(script.Parent.Parent.CharacterFacingController)

export type Target = {
	id: string,
	anchor: BasePart,
}

export type State = {
	-- The enemy under the crosshair, when there is no lock.
	soft: Target?,
	locked: Target?,
}

local TargetAssist = {}

-- How near the crosshair a body must be to be the soft target, as a fraction of the screen's height.
local SOFT_RADIUS = 0.08
-- A lock pressed with nothing under the crosshair takes the nearest enemy within this.
local ACQUIRE_RADIUS = 0.32
-- Studs from the character. A lock holds a little past where it can be made, so an enemy stepping
-- back does not drop it.
local MAX_RANGE = 60
local LOCK_RANGE = 75
-- Seconds a locked target may be out of sight before the lock lets go.
local SIGHT_GRACE = 1.0
-- Radians either side of the view's centre the camera leaves a locked target alone in: about the
-- middle 20% of the screen.
local DEADZONE = math.rad(12)
-- Past this, the player has dragged the target away, and the lock lets go.
local BREAK_ANGLE = math.rad(62)
-- How quickly the camera closes the gap once a locked target leaves the zone, per second.
local FOLLOW_RATE = 6
-- Mouse travel in pixels within the window that counts as a flick to the next target.
local FLICK_PIXELS = 150
local FLICK_WINDOW = 0.12
local FLICK_COOLDOWN = 0.35
-- How the camera holds a lock, by weapon class. "lazy" uses the zone above; "tight" keeps the target
-- centred, for weapons aimed by the camera itself (bows, once they exist).
local CAMERA_HOLD: { [string]: "lazy" | "tight" } = {}

local state: State = { soft = nil, locked = nil }
local cameraModifier: string? = nil
local outOfSightSince: number? = nil
local flickUntil = 0
local deltas: { { at: number, dx: number } } = {}
local started = false

local function active(): boolean
	local camera = CameraController.getInstance()
	return camera.enabled
		and camera.mode == "OverShoulder"
		and UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
end

local function rootOf(): BasePart?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function alive(target: Target?): boolean
	return target ~= nil and target.anchor.Parent ~= nil and EntityStore.isAlive(target.id)
end

-- Every enemy that could be a target: present, alive, streamed in, and of another faction.
local function candidates(): { Target }
	local character = Players.LocalPlayer.Character
	local mine = character and EntityUtils.getFaction(character)
	local localId = Registrar.getLocalEntityId()
	local out: { Target } = {}
	for _, entry in ipairs(EntityStore.getSnapshot()) do
		local anchor = entry.anchor
		local model = anchor and anchor.Parent
		if
			entry.present
			and anchor
			and model
			and model:IsA("Model")
			and entry.id ~= localId
			and EntityStore.isAlive(entry.id)
			and EntityUtils.getFaction(model) ~= mine
		then
			table.insert(out, { id = entry.id, anchor = anchor })
		end
	end
	return out
end

local function inSight(camera: Camera, target: Target): boolean
	local from = camera.CFrame.Position
	local ignore: { Instance } = { target.anchor.Parent :: Instance }
	local character = Players.LocalPlayer.Character
	if character then
		table.insert(ignore, character)
	end
	local projectiles = Workspace:FindFirstChild("Projectiles")
	if projectiles then
		table.insert(ignore, projectiles)
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	return Workspace:Raycast(from, target.anchor.Position - from, params) == nil
end

-- Studs below and above an enemy's root that its body spans, for measuring how near the crosshair
-- is to the body rather than to its centre: up close the centre can be well off the crosshair while
-- the body is right on it.
local BODY_BELOW = 2.5
local BODY_ABOVE = 2
local BODY_RADIUS = 1

-- Distance from the screen's centre to the target's body as a fraction of the screen's height, or
-- nil when it is behind the camera.
local function screenOffset(camera: Camera, position: Vector3): number?
	local point, onScreen = camera:WorldToViewportPoint(position)
	if not onScreen or point.Z <= 0 then
		return nil
	end
	local viewport = camera.ViewportSize
	local centre = viewport / 2
	local feet = camera:WorldToViewportPoint(position - Vector3.new(0, BODY_BELOW, 0))
	local head = camera:WorldToViewportPoint(position + Vector3.new(0, BODY_ABOVE, 0))
	local a = Vector2.new(feet.X, feet.Y)
	local b = Vector2.new(head.X, head.Y)
	local along = b - a
	local t = if along.Magnitude > 1e-3 then math.clamp((centre - a):Dot(along) / along:Dot(along), 0, 1) else 0
	-- The body is a column, not a line: its half-width at this distance comes off the gap.
	local radius = along.Magnitude / (BODY_BELOW + BODY_ABOVE) * BODY_RADIUS
	return math.max((centre - (a + along * t)).Magnitude - radius, 0) / viewport.Y
end

-- Signed angle of `position` from the camera's forward around the vertical, in the camera's own yaw
-- convention: positive is to the left.
local function bearingFromView(camera: Camera, position: Vector3): number
	local look = camera.CFrame.LookVector
	local toTarget = position - camera.CFrame.Position
	local viewYaw = math.atan2(-look.X, -look.Z)
	local targetYaw = math.atan2(-toTarget.X, -toTarget.Z)
	return (targetYaw - viewYaw + math.pi) % (2 * math.pi) - math.pi
end

-- The enemy nearest the crosshair within `radius`, in range and in sight.
local function nearestToCrosshair(camera: Camera, radius: number, root: BasePart): Target?
	local best: Target? = nil
	local bestScore = math.huge
	for _, target in ipairs(candidates()) do
		local distance = (target.anchor.Position - root.Position).Magnitude
		local offset = if distance <= MAX_RANGE then screenOffset(camera, target.anchor.Position) else nil
		if offset and offset <= radius then
			-- Nearest the crosshair first; distance only breaks near-ties, so a close enemy beside a
			-- far one directly behind it wins.
			local score = offset + distance * 0.0005
			if score < bestScore and inSight(camera, target) then
				best = target
				bestScore = score
			end
		end
	end
	return best
end

local function holdFor(): "lazy" | "tight"
	local classKey = BasicAttackProfileRegistry.classKeyOf(CombatLoadoutMirror.get())
	return CAMERA_HOLD[classKey] or "lazy"
end

function TargetAssist.release()
	state.locked = nil
	outOfSightSince = nil
	if cameraModifier then
		CameraController.getInstance():popModifier(cameraModifier)
		cameraModifier = nil
	end
end

local function lockOnto(target: Target)
	TargetAssist.release()
	state.locked = target
	state.soft = nil
	local anchor = target.anchor
	cameraModifier = CameraController.getInstance():pushModifier({
		trackTarget = {
			provider = function(): Vector3?
				return if anchor.Parent then anchor.Position else nil
			end,
			deadzone = if holdFor() == "tight" then 0 else DEADZONE,
			rate = FOLLOW_RATE,
		},
	})
end

-- Lock onto the soft target, or the enemy nearest the crosshair; or let go of the current lock.
function TargetAssist.toggleLock()
	if state.locked then
		TargetAssist.release()
		return
	end
	local camera = Workspace.CurrentCamera
	local root = rootOf()
	if not camera or not root or not active() then
		return
	end
	local target = if alive(state.soft) then state.soft else nearestToCrosshair(camera, ACQUIRE_RADIUS, root)
	if target then
		lockOnto(target)
	end
end

-- A quick sideways flick moves the lock to the nearest enemy on that side of the current one.
local function flickSwitch(camera: Camera, root: BasePart, direction: number)
	local current = state.locked
	if not current then
		return
	end
	local currentBearing = bearingFromView(camera, current.anchor.Position)
	local best: Target? = nil
	local bestGap = math.huge
	for _, target in ipairs(candidates()) do
		if target.id ~= current.id and (target.anchor.Position - root.Position).Magnitude <= MAX_RANGE then
			-- Mouse right turns the view right, which is toward smaller bearings.
			local gap = (currentBearing - bearingFromView(camera, target.anchor.Position)) * direction
			if gap > 0 and gap < bestGap and inSight(camera, target) then
				best = target
				bestGap = gap
			end
		end
	end
	if best then
		lockOnto(best)
	end
end

local function flickDirection(now: number): number?
	local sum = 0
	local kept = {}
	for _, delta in ipairs(deltas) do
		if now - delta.at <= FLICK_WINDOW then
			table.insert(kept, delta)
			sum += delta.dx
		end
	end
	deltas = kept
	if now < flickUntil or math.abs(sum) < FLICK_PIXELS then
		return nil
	end
	flickUntil = now + FLICK_COOLDOWN
	table.clear(deltas)
	return if sum > 0 then 1 else -1
end

local function update()
	local camera = Workspace.CurrentCamera
	local root = rootOf()
	if not camera or not root or not active() then
		state.soft = nil
		if state.locked then
			TargetAssist.release()
		end
		return
	end
	local now = os.clock()

	local locked = state.locked
	if locked then
		local direction = flickDirection(now)
		if direction then
			flickSwitch(camera, root, direction)
			locked = state.locked :: Target
		end
		if
			not alive(locked)
			or (locked.anchor.Position - root.Position).Magnitude > LOCK_RANGE
			or math.abs(bearingFromView(camera, locked.anchor.Position)) > BREAK_ANGLE
		then
			TargetAssist.release()
		elseif inSight(camera, locked) then
			outOfSightSince = nil
		else
			outOfSightSince = outOfSightSince or now
			if now - (outOfSightSince :: number) > SIGHT_GRACE then
				TargetAssist.release()
			end
		end
	end

	state.soft = if state.locked then nil else nearestToCrosshair(camera, SOFT_RADIUS, root)
end

function TargetAssist.get(): State
	return state
end

-- Whether the player is aiming: the over-the-shoulder camera with the cursor captured.
function TargetAssist.isActive(): boolean
	return active()
end

-- The target attacks go to now: the lock, else the soft target.
function TargetAssist.current(): Target?
	local target = state.locked or state.soft
	return if alive(target) then target else nil
end

-- Where to aim a shot at the current target, if there is one.
function TargetAssist.aimPoint(): Vector3?
	local target = TargetAssist.current()
	return if target then target.anchor.Position else nil
end

-- Turn the character to the current target for an attack lasting `duration` seconds; the camera
-- stays where it is. Nothing happens without a target.
function TargetAssist.faceForAttack(duration: number)
	local target = TargetAssist.current()
	if not target then
		return
	end
	local anchor = target.anchor
	CharacterFacingController.getInstance():faceToward(function(): Vector3?
		return if anchor.Parent then anchor.Position else nil
	end, duration)
end

function TargetAssist.start()
	if started then
		return
	end
	started = true
	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement and state.locked then
			table.insert(deltas, { at = os.clock(), dx = input.Delta.X })
		end
	end)
	-- Before the camera, so a lock released this frame no longer pulls it.
	RunService:BindToRenderStep("StrongestDungeonCrawler.TargetAssist", Enum.RenderPriority.Camera.Value - 1, update)
end

return TargetAssist
