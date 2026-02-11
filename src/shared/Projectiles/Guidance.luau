--!strict
-- Shared guidance helpers for steering modifiers (e.g., homing).

local Guidance = {}

function Guidance.computeInfluence(dist: number, startDist: number?, fullDist: number?): number
	if type(fullDist) ~= "number" then
		if type(startDist) == "number" then
			return if dist <= startDist then 1 else 0
		end
		return 1
	end
	local start = startDist
	if type(start) ~= "number" or start <= fullDist then
		start = fullDist
	end
	if dist <= fullDist then
		return 1
	end
	if dist >= start then
		return 0
	end
	return 1 - (dist - fullDist) / (start - fullDist)
end

function Guidance.rotateTowards(currentDir: Vector3, desiredDir: Vector3, maxTurnRad: number): Vector3
	if currentDir.Magnitude <= 1e-4 then
		return desiredDir
	end
	if desiredDir.Magnitude <= 1e-4 then
		return currentDir
	end
	local cur = currentDir.Unit
	local des = desiredDir.Unit
	local dot = math.clamp(cur:Dot(des), -1, 1)
	local angle = math.acos(dot)
	if angle <= 1e-4 then
		return des
	end
	local t = math.min(1, maxTurnRad / angle)
	return (cur:Lerp(des, t)).Unit
end

function Guidance.applyHoming(
	baseVel: Vector3,
	currentVel: Vector3,
	position: Vector3,
	targetPos: Vector3,
	dt: number,
	params: any,
	fallbackSpeed: number?
): (Vector3, number)
	local influence = (params and (params.influence or params.weight)) or 1
	local startDist = params and params.startDistance or nil
	local fullDist = params and params.fullDistance or nil
	local dist = (targetPos - position).Magnitude
	local blend = Guidance.computeInfluence(dist, startDist, fullDist) * influence
	if blend <= 1e-4 then
		return baseVel, 0
	end

	local desiredDir = targetPos - position
	if desiredDir.Magnitude <= 1e-4 then
		return baseVel, 0
	end

	local speed = currentVel.Magnitude
	if speed <= 1e-4 then
		speed = baseVel.Magnitude
	end
	if speed <= 1e-4 then
		speed = (params and params.speed) or fallbackSpeed or 30
	end

	local turnRate = (params and params.turnRate) or 360
	local maxTurnRad = math.rad(turnRate) * dt
	local curDir = if currentVel.Magnitude > 1e-4 then currentVel.Unit else baseVel.Unit
	if curDir.Magnitude <= 1e-4 then
		curDir = desiredDir.Unit
	end
	local newDir = Guidance.rotateTowards(curDir, desiredDir, maxTurnRad)
	local homingVel = newDir * speed
	local blended = baseVel:Lerp(homingVel, math.clamp(blend, 0, 1))
	return blended, math.clamp(blend, 0, 1)
end

return Guidance
