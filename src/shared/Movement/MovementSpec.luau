--!strict
-- MovementSpec: shared movement action schema + helpers (client/server).

export type MovementKind = "dash" | "roll"

export type DashSpec = {
	kind: "dash",
	id: string?,
	sourceSkill: string?,
	startTime: number,
	duration: number,
	distance: number,
	direction: Vector3,
	k: number,
	minFactor: number,
}

export type RollSpec = {
	kind: "roll",
	id: string?,
	sourceSkill: string?,
	startTime: number,
	duration: number,
	distance: number,
	direction: Vector3,
}

export type MovementSpec = DashSpec | RollSpec

local DEFAULT_DASH_K = 6
local DEFAULT_DASH_MIN_FACTOR = 0.15

local function normalizeDirection(direction: Vector3?): Vector3
	if typeof(direction) ~= "Vector3" then
		return Vector3.new(0, 0, -1)
	end
	if direction.Magnitude <= 1e-4 then
		return Vector3.new(0, 0, -1)
	end
	return direction.Unit
end

local function buildDashSpec(params: {
	id: string?,
	sourceSkill: string?,
	startTime: number,
	duration: number?,
	distance: number?,
	direction: Vector3?,
	k: number?,
	minFactor: number?,
}): DashSpec
	local duration = math.max(params.duration or 0, 0)
	local distance = math.max(params.distance or 0, 0)
	local k = params.k or DEFAULT_DASH_K
	local minFactor = params.minFactor or DEFAULT_DASH_MIN_FACTOR
	return {
		kind = "dash",
		id = params.id,
		sourceSkill = params.sourceSkill,
		startTime = params.startTime,
		duration = duration,
		distance = distance,
		direction = normalizeDirection(params.direction),
		k = k,
		minFactor = minFactor,
	}
end

local function buildRollSpec(params: {
	id: string?,
	sourceSkill: string?,
	startTime: number,
	duration: number?,
	distance: number?,
	direction: Vector3?,
}): RollSpec
	local duration = math.max(params.duration or 0, 0)
	local distance = math.max(params.distance or 0, 0)
	return {
		kind = "roll",
		id = params.id,
		sourceSkill = params.sourceSkill,
		startTime = params.startTime,
		duration = duration,
		distance = distance,
		direction = normalizeDirection(params.direction),
	}
end

local function computeDashVelocity(spec: DashSpec, elapsed: number): Vector3
	if spec.duration <= 0 then
		return Vector3.zero
	end
	local t = math.clamp(elapsed / spec.duration, 0, 1)
	local effectiveK = 1 - spec.minFactor
	local denom = 1 - math.exp(-spec.k * effectiveK)
	local v0 = if denom > 0 then (spec.distance * spec.k) / (spec.duration * denom) else 0
	local decay = math.exp(-spec.k * t)
	local speedFactor = math.max(decay, spec.minFactor)
	return spec.direction * (v0 * speedFactor)
end

local function computeRollVelocity(spec: RollSpec, elapsed: number): Vector3
	if spec.duration <= 0 then
		return Vector3.zero
	end
	local t = math.clamp(elapsed / spec.duration, 0, 1)
	local speedFactor = math.sin(math.pi * t)
	local v0 = (spec.distance * math.pi) / (2 * spec.duration)
	return spec.direction * (v0 * speedFactor)
end

local function computeVelocity(spec: MovementSpec, elapsed: number): Vector3
	if spec.kind == "dash" then
		return computeDashVelocity(spec, elapsed)
	end
	if spec.kind == "roll" then
		return computeRollVelocity(spec, elapsed)
	end
	return Vector3.zero
end

return {
	DEFAULT_DASH_K = DEFAULT_DASH_K,
	DEFAULT_DASH_MIN_FACTOR = DEFAULT_DASH_MIN_FACTOR,
	buildDashSpec = buildDashSpec,
	buildRollSpec = buildRollSpec,
	computeDashVelocity = computeDashVelocity,
	computeRollVelocity = computeRollVelocity,
	computeVelocity = computeVelocity,
}
