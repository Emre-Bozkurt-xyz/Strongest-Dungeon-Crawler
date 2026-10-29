--!strict
-- AttackLunge: a short step into each melee swing, so a blow commits the body behind it instead of
-- swinging from where the character happened to stand.
--
-- With a target (the lock, else the soft target) the step closes the gap to where the swing reaches
-- comfortably, so a press at the edge of reach connects rather than whiffing by a stud. Without one
-- it is a token step forward. It never runs over another movement (a dash, a roll, a push), and
-- never in the air.
--
-- Played through the same mover as a dash. The character is the player's own, so this is ordinary
-- client movement as far as the server is concerned.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MovementSpec = require(ReplicatedStorage.Shared.Movement.MovementSpec)
local Clock = require(ReplicatedStorage.Shared.Time.Clock)
local MovementController = require(script.Parent.MovementController)
local TargetAssist = require(script.Parent.Parent.SkillsFramework.TargetAssist)

local AttackLunge = {}

-- Studs. The step with no target, and the most a target can pull the character in.
local IDLE_STEP = 0.6
local MAX_STEP = 2.5
-- Where the step stops short of the target's centre, as a share of the swing's reach: well inside
-- it, so the target can drift a little and still be struck.
local STOP_SHARE = 0.55
-- Seconds the step takes. Short enough to be over before the earliest swing's hit.
local DURATION = 0.14

local function flat(vector: Vector3): Vector3
	return Vector3.new(vector.X, 0, vector.Z)
end

-- Step into a swing reaching `range` studs.
function AttackLunge.start(range: number)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.FloorMaterial == Enum.Material.Air then
		return
	end
	if MovementController.isActive() then
		return
	end

	local direction = flat(root.CFrame.LookVector)
	local distance = IDLE_STEP
	local target = TargetAssist.current()
	if target then
		local toTarget = flat(target.anchor.Position - root.Position)
		local gap = toTarget.Magnitude - range * STOP_SHARE
		-- A target farther than one full step past reach is not this swing's to chase.
		if toTarget.Magnitude > 1e-3 and gap <= MAX_STEP + range * (1 - STOP_SHARE) then
			direction = toTarget.Unit
			distance = math.clamp(gap, 0, MAX_STEP)
		end
	end
	if distance <= 0.05 or direction.Magnitude < 1e-3 then
		return
	end

	MovementController.startLocalDash(MovementSpec.buildDashSpec({
		sourceSkill = "attackLunge",
		startTime = Clock.serverNow(),
		duration = DURATION,
		distance = distance,
		direction = direction.Unit,
	}))
end

return AttackLunge
