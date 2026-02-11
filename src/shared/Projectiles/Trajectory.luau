--!strict
-- Shared projectile trajectory math for deterministic client/server sims.

local Trajectory = {}
local PatternUtils = require(script.Parent.PatternUtils)

local function resolveParams(params: any): any
	if type(params) ~= "table" then
		return nil
	end
	if params.movementParams and type(params.movementParams) == "table" then
		return params.movementParams
	end
	return params
end

function Trajectory.cascadingPos(t: number, startPos: Vector3, params: any): Vector3
	local mp = resolveParams(params)
	if not mp then
		return startPos
	end
	local targetPos = mp.targetPos
	if typeof(targetPos) ~= "Vector3" then
		return startPos
	end
	local flightTime = mp.flightTime
	if type(flightTime) ~= "number" or flightTime <= 1e-4 then
		flightTime = 0.5
	end
	local tNorm = math.clamp(t / flightTime, 0, 1)
	local basePos = startPos:Lerp(targetPos, tNorm)

	local lateral = mp.lateral
	if typeof(lateral) ~= "Vector3" then
		lateral = Vector3.new(0, 0, 0)
	end
	local amplitude = mp.amplitude
	if type(amplitude) ~= "number" then
		amplitude = 0
	end
	local frequency = mp.frequency
	if type(frequency) ~= "number" then
		frequency = 1
	end
	local phase = mp.phase
	if type(phase) ~= "number" then
		phase = 0
	end

	local envelope = math.sin(math.pi * tNorm)
	local osc = math.sin(phase + tNorm * frequency * math.pi * 2)
	local offset = lateral * (amplitude * envelope * osc)
	return basePos + offset
end

function Trajectory.cascadingVel(t: number, startPos: Vector3, params: any, dt: number?): Vector3
	local step = dt
	if type(step) ~= "number" or step <= 1e-5 then
		step = 1 / 60
	end
	local p1 = Trajectory.cascadingPos(t, startPos, params)
	local p2 = Trajectory.cascadingPos(t + step, startPos, params)
	return (p2 - p1) / step
end

function Trajectory.arcPos(t: number, startPos: Vector3, params: any): Vector3
	local mp = resolveParams(params)
	if not mp then
		return startPos
	end
	local targetPos = mp.targetPos
	if typeof(targetPos) ~= "Vector3" then
		return startPos
	end
	local flightTime = mp.flightTime
	if type(flightTime) ~= "number" or flightTime <= 1e-4 then
		flightTime = 0.5
	end
	local tNorm = math.clamp(t / flightTime, 0, 1)
	local basePos = startPos:Lerp(targetPos, tNorm)

	local amplitude = mp.amplitude
	if type(amplitude) ~= "number" then
		amplitude = 0
	end
	local orientationDeg = mp.orientationDeg
	if type(orientationDeg) ~= "number" then
		orientationDeg = 0
	end

	local _forward, right, up = PatternUtils.makeBasis(targetPos - startPos)
	local plane = mp.plane
	local basisB = up
	if plane == "horizontal" then
		basisB = _forward
	end
	local rad = math.rad(orientationDeg)
	local sideSign = mp.sideSign
	local rightDir = right
	if type(sideSign) == "number" and sideSign ~= 0 then
		rightDir = right * sideSign
	end
	local lateral = rightDir * math.cos(rad) + basisB * math.sin(rad)
	if lateral.Magnitude <= 1e-4 then
		lateral = right
	end
	local offset = lateral.Unit * (amplitude * math.sin(math.pi * tNorm))
	return basePos + offset
end

function Trajectory.arcVel(t: number, startPos: Vector3, params: any, dt: number?): Vector3
	local step = dt
	if type(step) ~= "number" or step <= 1e-5 then
		step = 1 / 60
	end
	local p1 = Trajectory.arcPos(t, startPos, params)
	local p2 = Trajectory.arcPos(t + step, startPos, params)
	return (p2 - p1) / step
end

function Trajectory.computeBase(
	movementType: string,
	t: number,
	startPos: Vector3,
	startVel: Vector3,
	params: any
): (Vector3, Vector3)
	if movementType == "linear" then
		return startPos + startVel * t, startVel
	end
	if movementType == "parabolic" then
		local g = (params and params.gravity) or 0
		local pos = startPos + startVel * t + Vector3.new(0, 0.5 * g * t * t, 0)
		local vel = startVel + Vector3.new(0, g * t, 0)
		return pos, vel
	end
	if movementType == "cascading" then
		return Trajectory.cascadingPos(t, startPos, params), Trajectory.cascadingVel(t, startPos, params, 1 / 60)
	end
	if movementType == "arc" then
		return Trajectory.arcPos(t, startPos, params), Trajectory.arcVel(t, startPos, params, 1 / 60)
	end
	return startPos + startVel * t, startVel
end

return Trajectory
