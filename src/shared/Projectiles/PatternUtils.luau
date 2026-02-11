--!strict
-- Shared helpers for projectile patterns (client + server deterministic math).

local PatternUtils = {}

function PatternUtils.randomInUnitCircle(rng: Random): Vector2
	local angle = rng:NextNumber(0, math.pi * 2)
	local radius = math.sqrt(rng:NextNumber())
	return Vector2.new(math.cos(angle) * radius, math.sin(angle) * radius)
end

function PatternUtils.makeBasis(from: Vector3): (Vector3, Vector3, Vector3)
	local forward = from.Magnitude > 1e-4 and from.Unit or Vector3.new(0, 0, -1)
	local up = Vector3.new(0, 1, 0)
	local right = forward:Cross(up)
	if right.Magnitude <= 1e-3 then
		right = forward:Cross(Vector3.new(1, 0, 0))
	end
	right = right.Unit
	up = right:Cross(forward).Unit
	return forward, right, up
end

function PatternUtils.computeGroupPhase(index: number, groupSize: number, phaseJitter: number, rng: Random): (number, number)
	local groupIndex = math.floor((index - 1) / math.max(1, groupSize))
	local sideSign = if (groupIndex % 2) == 0 then 1 else -1
	local phaseBase = if sideSign > 0 then 0 else math.pi
	local phase = phaseBase + rng:NextNumber(-phaseJitter, phaseJitter)
	return sideSign, phase
end

function PatternUtils.computeLateral(
	right: Vector3,
	up: Vector3,
	sideSign: number,
	verticalBias: number,
	verticalBiasJitter: number,
	rng: Random
): Vector3
	local verticalSign = if rng:NextNumber() < 0.5 then -1 else 1
	local verticalScale = verticalBias * rng:NextNumber(1 - verticalBiasJitter, 1 + verticalBiasJitter)
	local lateral = (right * sideSign + up * verticalSign * verticalScale)
	if lateral.Magnitude <= 1e-4 then
		lateral = right
	end
	return lateral.Unit
end

function PatternUtils.pickArcOrientation(
	rng: Random,
	minDeg: number?,
	maxDeg: number?,
	symmetric: boolean?
): number
	local minAngle = minDeg or 0
	local maxAngle = maxDeg or 360
	if maxAngle < minAngle then
		minAngle, maxAngle = maxAngle, minAngle
	end
	if symmetric then
		local sign = if rng:NextNumber() < 0.5 then -1 else 1
		local mag = rng:NextNumber(minAngle, maxAngle)
		return mag * sign
	end
	return rng:NextNumber(minAngle, maxAngle)
end

return PatternUtils
