--!strict
-- ClientHitDetection: Lightweight client-side hit detection for immediate visual feedback
-- This is NOT authoritative - it's purely for UX responsiveness (flash, sound, shake)
-- Server remains authoritative for actual damage, stagger, etc.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- Reserved for future reveal-based filtering:
-- local EntityRevealStore = require(script.Parent.Parent.EntityRevealStore)

local ClientHitDetection = {}

-- Configuration
local DEFAULT_CONE_ANGLE = 60 -- degrees
local DEFAULT_CONE_RANGE = 8 -- studs

export type HitDetectionResult = {
	hit: boolean,
	targets: { Model },
	primaryTarget: Model?, -- Closest target
	position: Vector3?, -- Hit position (for FX placement)
}

export type ConeOptions = {
	origin: CFrame?,
	angleDeg: number?,
	range: number?,
	maxTargets: number?,
}

-- Get the local player's character
local function getLocalCharacter(): Model?
	local player = Players.LocalPlayer
	return player and player.Character
end

-- Get character position and look direction
local function getCharacterCFrame(character: Model): CFrame?
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return hrp and hrp.CFrame
end

-- Check if a model is a valid target (has humanoid, is revealed, not local player)
local function isValidTarget(model: Model): boolean
	-- Must have humanoid
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end

	-- Must not be local player
	local localChar = getLocalCharacter()
	if model == localChar then
		return false
	end

	-- Check for EntityId attribute (entities registered in the system)
	-- For now, we don't filter by reveal status - allow all entities with humanoids
	-- This could be changed to filter using EntityRevealStore if needed
	local _entityId = model:GetAttribute("EntityId") :: string?

	return true
end

-- Get center position of a model
local function getModelCenter(model: Model): Vector3?
	local hrp = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp then
		return hrp.Position
	end
	return model:GetPivot().Position
end

-- Simple cone check: is point within cone from origin looking in direction?
local function isInCone(origin: Vector3, direction: Vector3, point: Vector3, angleDeg: number, range: number): boolean
	local toPoint = point - origin
	local distance = toPoint.Magnitude

	-- Range check
	if distance > range then
		return false
	end

	-- Angle check
	local dot = direction.Unit:Dot(toPoint.Unit)
	local angleRad = math.rad(angleDeg / 2) -- Half angle for cone
	local minDot = math.cos(angleRad)

	return dot >= minDot
end

-- Perform a cone-shaped hit detection query
-- Returns all valid targets within the cone
function ClientHitDetection.queryCone(opts: ConeOptions?): HitDetectionResult
	local options: ConeOptions = opts or {} :: ConeOptions
	local character = getLocalCharacter()

	if not character then
		return { hit = false, targets = {}, primaryTarget = nil, position = nil }
	end

	-- Get origin from options or character
	local origin = options.origin
	if not origin then
		origin = getCharacterCFrame(character)
	end

	if not origin then
		return { hit = false, targets = {}, primaryTarget = nil, position = nil }
	end

	local angleDeg = options.angleDeg or DEFAULT_CONE_ANGLE
	local range = options.range or DEFAULT_CONE_RANGE
	local maxTargets = options.maxTargets or 10

	local originPos = origin.Position
	local lookDir = origin.LookVector

	-- Gather candidates using workspace spatial query
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { character :: Instance }

	-- Query a sphere first, then filter by cone
	local parts = Workspace:GetPartBoundsInRadius(originPos, range, overlapParams)

	-- Track unique models we've processed
	local processedModels: { [Model]: boolean } = {}
	local targets: { Model } = {}
	local targetDistances: { [Model]: number } = {}

	for _, part in ipairs(parts) do
		-- Find the character model this part belongs to
		local model = part:FindFirstAncestorOfClass("Model")
		if not model or processedModels[model] then
			continue
		end
		processedModels[model] = true

		-- Check if valid target
		if not isValidTarget(model) then
			continue
		end

		-- Get model center
		local modelCenter = getModelCenter(model)
		if not modelCenter then
			continue
		end

		-- Check if in cone
		if not isInCone(originPos, lookDir, modelCenter, angleDeg, range) then
			continue
		end

		-- Valid target!
		table.insert(targets, model)
		targetDistances[model] = (modelCenter - originPos).Magnitude

		if #targets >= maxTargets then
			break
		end
	end

	-- Sort by distance (closest first)
	table.sort(targets, function(a, b)
		return (targetDistances[a] or math.huge) < (targetDistances[b] or math.huge)
	end)

	-- Get primary target (closest)
	local primaryTarget = targets[1]
	local hitPosition: Vector3? = nil
	if primaryTarget then
		hitPosition = getModelCenter(primaryTarget)
	end

	return {
		hit = #targets > 0,
		targets = targets,
		primaryTarget = primaryTarget,
		position = hitPosition,
	}
end

-- Perform a simple sphere query (for AOE effects)
function ClientHitDetection.querySphere(center: Vector3, radius: number, maxTargets: number?): HitDetectionResult
	local character = getLocalCharacter()
	local excludeList: { Instance } = character and { character :: Instance } or {}

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = excludeList

	local parts = Workspace:GetPartBoundsInRadius(center, radius, overlapParams)

	local processedModels: { [Model]: boolean } = {}
	local targets: { Model } = {}
	local targetDistances: { [Model]: number } = {}
	local limit = maxTargets or 10

	for _, part in ipairs(parts) do
		local model = part:FindFirstAncestorOfClass("Model")
		if not model or processedModels[model] then
			continue
		end
		processedModels[model] = true

		if not isValidTarget(model) then
			continue
		end

		local modelCenter = getModelCenter(model)
		if modelCenter then
			table.insert(targets, model)
			targetDistances[model] = (modelCenter - center).Magnitude
		end

		if #targets >= limit then
			break
		end
	end

	table.sort(targets, function(a, b)
		return (targetDistances[a] or math.huge) < (targetDistances[b] or math.huge)
	end)

	local primaryTarget = targets[1]

	return {
		hit = #targets > 0,
		targets = targets,
		primaryTarget = primaryTarget,
		position = primaryTarget and getModelCenter(primaryTarget) or nil,
	}
end

-- Perform a raycast query (for projectiles or precise targeting)
function ClientHitDetection.queryRay(origin: Vector3, direction: Vector3, distance: number): HitDetectionResult
	local character = getLocalCharacter()
	local excludeList: { Instance } = character and { character :: Instance } or {}

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = excludeList

	local result = Workspace:Raycast(origin, direction.Unit * distance, rayParams)

	if result and result.Instance then
		local model = result.Instance:FindFirstAncestorOfClass("Model")
		if model and isValidTarget(model) then
			return {
				hit = true,
				targets = { model },
				primaryTarget = model,
				position = result.Position,
			}
		end
	end

	return { hit = false, targets = {}, primaryTarget = nil, position = nil }
end

return ClientHitDetection
