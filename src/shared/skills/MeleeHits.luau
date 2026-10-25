--!strict
-- MeleeHits: when and where a melee hit lands, and who it reaches, read the same way by both peers.
--
-- The server resolves damage from these hits; the client predicts the reaction to the same hits
-- (flash, sound, hitstop) on the same schedule and against the same cone. One definition is what
-- keeps the prediction agreeing with the server -- a cone or timing that exists twice drifts.
--
-- Times are seconds from the start of the cast or combo step, before tempo scaling.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local SkillSpecTypes = require(ReplicatedStorage.Shared.skills.SkillSpecTypes)
local BasicAttackProfileTypes = require(ReplicatedStorage.Shared.skills.BasicAttackProfileTypes)

export type Hit = {
	t: number,
	-- Degrees the cone is turned from the caster's facing, about the up axis.
	yaw: number,
	-- Full cone angle in degrees, and reach in studs.
	angle: number,
	range: number,
	-- Freeze the caster's swing briefly on contact. Off for hits that are not a weapon meeting a body.
	hitstop: boolean,
}

local MeleeHits = {}

local DEFAULT_ANGLE = 50
local DEFAULT_RANGE = 8

function MeleeHits.fromSpec(spec: SkillSpecTypes.HitSpec): Hit
	return {
		t = spec.t,
		yaw = spec.yaw or 0,
		angle = spec.coneAngle or DEFAULT_ANGLE,
		range = spec.coneRange or DEFAULT_RANGE,
		hitstop = spec.hitstop ~= false,
	}
end

function MeleeHits.fromSpecs(specs: { SkillSpecTypes.HitSpec }?): { Hit }
	local hits = {}
	for _, spec in ipairs(specs or {}) do
		table.insert(hits, MeleeHits.fromSpec(spec))
	end
	return hits
end

-- A profile step's cone (angle, range): its own override, else the profile's. Also the shape a
-- projectile step degrades to when the equipped weapon declares no projectile.
function MeleeHits.profileCone(profile: BasicAttackProfileTypes.BasicAttackProfile, step: number): (number, number)
	local stepSpec = profile.steps[step] or profile.steps[#profile.steps]
	return stepSpec.coneAngle or profile.hitCone.angle, stepSpec.coneRange or profile.hitCone.range
end

-- The cone hit for one step of a basic attack profile. `t` is the step's authored hit delay.
-- Projectile steps return nil: what they hit is decided by flight, not by a cone at a moment.
function MeleeHits.forProfileStep(profile: BasicAttackProfileTypes.BasicAttackProfile, step: number): Hit?
	local stepSpec = profile.steps[step] or profile.steps[#profile.steps]
	if (stepSpec.delivery or "cone") ~= "cone" then
		return nil
	end
	local hitDelays = profile.combo.hitDelays
	local angle, range = MeleeHits.profileCone(profile, step)
	return {
		t = if hitDelays and hitDelays[step] then hitDelays[step] else 0,
		yaw = 0,
		angle = angle,
		range = range,
		hitstop = true,
	}
end

function MeleeHits.originFor(root: CFrame, hit: Hit): CFrame
	return root * CFrame.Angles(0, math.rad(hit.yaw), 0)
end

local function modelOf(part: BasePart): Model?
	local current: Instance? = part.Parent
	while current do
		if current:IsA("Model") then
			return current
		end
		current = current.Parent
	end
	return nil
end

-- Models reached by a cone: any part of the model within `range` of the origin, with its root
-- within half of `angle` of the origin's facing. The reach test uses part bounds so a large body is
-- hit at its surface rather than its centre; the angle uses the root so it does not depend on which
-- limb happens to be nearest.
--
-- `accept` filters candidates (faction, liveness, the caster themselves) and runs once per model.
function MeleeHits.queryCone(
	origin: CFrame,
	angle: number,
	range: number,
	overlap: OverlapParams?,
	accept: (Model) -> boolean,
	maxTargets: number?
): { Model }
	local results: { Model } = {}
	local visited: { [Model]: true } = {}
	local forward = origin.LookVector
	local minDot = math.cos(math.rad(angle * 0.5))
	for _, part in ipairs(Workspace:GetPartBoundsInRadius(origin.Position, range, overlap)) do
		local model = modelOf(part)
		if not model or visited[model] then
			continue
		end
		visited[model] = true
		local root = model:FindFirstChild("HumanoidRootPart")
		if not (root and root:IsA("BasePart")) then
			continue
		end
		local toRoot = root.Position - origin.Position
		if toRoot.Magnitude <= 0 or forward:Dot(toRoot.Unit) < minDot then
			continue
		end
		if accept(model) then
			table.insert(results, model)
			if maxTargets and #results >= maxTargets then
				break
			end
		end
	end
	return results
end

return MeleeHits
