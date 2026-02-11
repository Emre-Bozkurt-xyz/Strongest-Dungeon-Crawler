--!strict
-- Spawn-only ProjectileService (clean): server-side logic and spawn-only visual recipes

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

local EntityUtils = require(ReplicatedStorage.Shared.EntityUtils)
local Trajectory = require(ReplicatedStorage.Shared.Projectiles.Trajectory)
local Guidance = require(ReplicatedStorage.Shared.Projectiles.Guidance)
local ProjectileEvent = require(script.Parent.ProjectileEvent)
local Registrar = require(script.Parent.Registrar)
local DebugConfig = require(ReplicatedStorage.Shared.Debug.DebugConfig)

local ProjectileService = {}
ProjectileService.__index = ProjectileService

-- Active logical projectiles (server-side only)
local activeProjectiles: { [number]: any } = {}
local nextId = 1
local debugVisuals: { [number]: BasePart } = {}
local debugFolder: Folder? = nil

local function getDebugFolder(): Folder
	if debugFolder and debugFolder.Parent then
		return debugFolder
	end
	local folder = Workspace:FindFirstChild("_ProjectileDebug")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "_ProjectileDebug"
		folder.Parent = Workspace
	end
	debugFolder = folder :: Folder
	return folder
end

local function updateDebugVisual(id: number, position: Vector3)
	if not DebugConfig.isEnabled("projectiles") then
		return
	end
	local part = debugVisuals[id]
	if not part then
		part = Instance.new("Part")
		part.Name = "ProjectileDebug"
		part.Size = Vector3.new(0.3, 0.3, 0.3)
		part.Shape = Enum.PartType.Ball
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Material = Enum.Material.Neon
		part.Color = Color3.fromRGB(120, 220, 255)
		part.Parent = getDebugFolder()
		debugVisuals[id] = part
	end
	part.Position = position
end

local function destroyDebugVisual(id: number)
	local part = debugVisuals[id]
	if part then
		debugVisuals[id] = nil
		part:Destroy()
	end
end

-- Movement registry (closed-form formulas or per-tick integrators can be registered)
local movementTypes: { [string]: (t: number, startPos: Vector3, startVel: Vector3, params: any) -> Vector3 } = {}

-- Linear closed-form: p(t) = p0 + v0 * t
movementTypes["linear"] = function(t, p0, v0, _)
	return p0 + v0 * t
end

-- Parabolic closed-form: p(t) = p0 + v0 * t + 0.5 * gravity * t^2 (gravity is scalar, negative for down)
movementTypes["parabolic"] = function(t, p0, v0, params)
	local g = params and params.gravity or -Workspace.Gravity
	return p0 + v0 * t + Vector3.new(0, 0.5 * g * t * t, 0)
end

-- Cascading (sinusoidal) closed-form shared with client.
movementTypes["cascading"] = function(t, p0, _v0, params)
	return Trajectory.cascadingPos(t, p0, params)
end

-- Arc (half sine wave) closed-form shared with client.
movementTypes["arc"] = function(t, p0, _v0, params)
	return Trajectory.arcPos(t, p0, params)
end

function ProjectileService.registerMovementType(
	name: string,
	fn: (
		t: number,
		startPos: Vector3,
		startVel: Vector3,
		params: any
	) -> Vector3
)
	movementTypes[name] = fn
end

-- Helper: broadcast payload to nearby players if radius provided, otherwise to all clients
local function broadcastPayload(position: Vector3?, radius: number?, payload: any)
	if radius == nil then
		ProjectileEvent:FireAllClients(payload)
		return
	end
	-- send only to players whose character primary part is within radius
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if char and char.PrimaryPart then
			local dist = (char.PrimaryPart.Position - (position or char.PrimaryPart.Position)).Magnitude
			if dist <= radius then
				ProjectileEvent:FireClient(player, payload)
			end
		end
	end
end

type SpawnParams = {
	templateKey: string?,
	cframe: CFrame?,
	velocity: Vector3?,
	movementParams: any?,
	token: string?,
	skillName: string?,
	launchSpeed: number?,
	gravity: number?,
	movementType: string?,
	lifetime: number?,
	owner: Instance?,
	faction: string?,
	radius: number?,
	pierce: number?,
	onHit: ((proj: any, hitPart: BasePart, hitEntity: Instance, hitResult: RaycastResult?) -> boolean?)?,
	onUpdate: ((proj: any, dt: number) -> ())?,
	onDestroy: ((proj: any) -> ())?,
	onEnd: ((proj: any, endPos: Vector3) -> ())?,
	extraData: any?,
	guidance: {
		kind: "homing"?,
		targetEntityId: string?,
		targetTag: string?,
		factionRelation: ("ally" | "enemy" | "neutral")?,
		maxRange: number?,
		turnRate: number?, -- deg/s
		reacquire: boolean?,
		maxHomingTime: number?,
	}?,
	guidanceStack: { [number]: any }?,
	-- server only: if set, server will only notify clients within this radius (studs)
	notifyRadius: number?,
	-- optional attachment info for spawn-and-hold patterns (client attaches when ownerEntityId matches local entity)
	attach: {
		ownerEntityId: string?,
		partName: string?,
		token: string?,
	}?,
}

local function getEntityRoot(model: Model?): BasePart?
	if not model then
		return nil
	end
	return model:FindFirstChild("HumanoidRootPart") :: BasePart? or model.PrimaryPart
end

local function resolveEntityFromPart(part: BasePart?): Model?
	local current: Instance? = part
	while current do
		if current:IsA("Model") and current:GetAttribute("EntityId") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function getOwnerEntityId(owner: any): string?
	if not owner then
		return nil
	end
	if typeof(owner) == "Instance" and owner:IsA("Player") then
		return Registrar.getPlayerId(owner)
	end
	if typeof(owner) == "Instance" and owner:IsA("Model") then
		return Registrar.getEntityId(owner)
	end
	return nil
end

local function isRelationMatch(casterFaction: string, targetFaction: string, relation: string?): boolean
	if relation == "ally" then
		return casterFaction == targetFaction
	elseif relation == "enemy" then
		return casterFaction ~= targetFaction
	elseif relation == "neutral" then
		return true
	end
	return true
end

local function sanitizeGuidance(g: any?): any?
	if type(g) ~= "table" then
		return nil
	end
	if g.kind ~= "homing" then
		return nil
	end
	return {
		kind = "homing",
		targetEntityId = g.targetEntityId,
		turnRate = g.turnRate,
		maxRange = g.maxRange,
		targetTag = g.targetTag,
		factionRelation = g.factionRelation,
		reacquire = g.reacquire,
		maxHomingTime = g.maxHomingTime,
		influence = g.influence or g.weight,
		startDistance = g.startDistance,
		fullDistance = g.fullDistance,
	}
end

local function sanitizeGuidanceStack(stack: any?): { [number]: any }?
	if type(stack) ~= "table" then
		return nil
	end
	local result = {}
	for _, entry in ipairs(stack) do
		local cleaned = sanitizeGuidance(entry)
		if cleaned then
			table.insert(result, cleaned)
		end
	end
	if #result == 0 then
		return nil
	end
	return result
end

local function selectHomingTarget(proj: any, g: any?): string?
	local guide = g or proj.guidance
	if not guide or guide.kind ~= "homing" then
		return nil
	end
	local casterFaction = proj.faction or "Neutral"
	local maxRange = guide.maxRange
	local tag = guide.targetTag
	local relation = guide.factionRelation or "enemy"

	local bestId = nil
	local bestDist = nil
	for _, entity in ipairs(Registrar.getAllEntities()) do
		if entity and entity.Parent then
			if proj.owner and entity == proj.owner then
				continue
			end
			if tag and not CollectionService:HasTag(entity, tag) then
				continue
			end
			local targetFaction = EntityUtils.getFaction(entity)
			if not isRelationMatch(casterFaction, targetFaction, relation) then
				continue
			end
			local root = getEntityRoot(entity)
			if root then
				local dist = (root.Position - proj.position).Magnitude
			if not maxRange or dist <= maxRange then
				if not bestDist or dist < bestDist then
					bestDist = dist
					bestId = Registrar.getEntityId(entity)
				end
			end
			end
		end
	end
	return bestId
end

local function rotateTowards(currentDir: Vector3, desiredDir: Vector3, maxTurnRad: number): Vector3
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

local function updateGuidance(proj: any, dt: number)
	if proj.attach then
		return
	end
	local g = proj.guidance
	if not g or g.kind ~= "homing" then
		return
	end
	if g.maxHomingTime and proj.age and proj.age >= g.maxHomingTime then
		return
	end
	local targetId = g.targetEntityId
	local target = targetId and Registrar.getEntityById(targetId) or nil
	if (not target or not target.Parent) and g.reacquire then
		local newId = selectHomingTarget(proj, g)
		if newId then
			g.targetEntityId = newId
			target = Registrar.getEntityById(newId)
		end
	end
	if not target or not target.Parent then
		return
	end
	local root = getEntityRoot(target)
	if not root then
		return
	end
	local desiredDir = root.Position - proj.position
	if desiredDir.Magnitude <= 1e-4 then
		return
	end
	local speed = proj.velocity and proj.velocity.Magnitude or 0
	if speed <= 1e-4 then
		if proj.launchSpeed and type(proj.launchSpeed) == "number" then
			speed = proj.launchSpeed
		else
			speed = 30
		end
	end
	local turnRate = g.turnRate or 360
	local maxTurnRad = math.rad(turnRate) * dt
	local curDir = if proj.velocity and proj.velocity.Magnitude > 1e-4 then proj.velocity.Unit else desiredDir.Unit
	local newDir = rotateTowards(curDir, desiredDir, maxTurnRad)
	proj.velocity = newDir * speed
end

function ProjectileService.spawnProjectile(params: SpawnParams): number
	-- Allow spawn requests that either include a cframe (instant spawn) or an attach hint
	-- (spawn-and-hold). templateKey is required.
	assert(params and params.templateKey, "spawnProjectile: missing templateKey")

	local id = nextId
	nextId += 1

	-- Resolve start position: prefer explicit cframe, else try to resolve from attach owner
	local resolvedPos: Vector3 = Vector3.new()
	if params.cframe then
		resolvedPos = params.cframe.Position
	elseif params.attach and params.attach.ownerEntityId then
		local ownerEntity = Registrar.getEntityById(params.attach.ownerEntityId)
		if ownerEntity then
			local part = ownerEntity:FindFirstChild(params.attach.partName, true)
			if part then
				if part:IsA("Attachment") then
					resolvedPos = part.WorldCFrame.Position
				elseif part:IsA("BasePart") then
					resolvedPos = part.Position
				end
			end
			if resolvedPos.Magnitude <= 1e-4 then
				local root = getEntityRoot(ownerEntity)
				if root then
					resolvedPos = root.Position
				end
			end
		end
	end

	local proj = {
		id = id,
		position = resolvedPos,
		startPosition = resolvedPos,
		velocity = params.velocity or Vector3.new(),
		startVelocity = params.velocity or Vector3.new(),
		movementParams = params.movementParams,
		token = params.token,
		skillName = params.skillName,
		launchSpeed = params.launchSpeed,
		movementType = params.movementType or "linear",
		gravity = params.gravity,
		lifetime = params.lifetime or 5,
		age = 0,
		owner = params.owner,
		ownerEntityId = getOwnerEntityId(params.owner),
		faction = params.faction or (params.owner and EntityUtils.getFaction(params.owner)) or "Neutral",
		radius = params.radius,
		pierce = params.pierce or 1,
		onHit = params.onHit,
		onUpdate = params.onUpdate,
		onDestroy = params.onDestroy,
		onEnd = params.onEnd,
		extraData = params.extraData,
		guidance = params.guidance,
		guidanceStack = params.guidanceStack,
		templateKey = params.templateKey or "",
		_alreadyHit = {},
		seq = 1,
		notifyRadius = params.notifyRadius,
		attach = params.attach,
	}

	if proj.guidance and proj.guidance.kind == "homing" and not proj.guidance.targetEntityId then
		proj.guidance.targetEntityId = selectHomingTarget(proj, proj.guidance)
	end
	if proj.guidanceStack then
		for _, g in ipairs(proj.guidanceStack) do
			if g.kind == "homing" and not g.targetEntityId then
				g.targetEntityId = selectHomingTarget(proj, g)
			end
		end
	end

	activeProjectiles[id] = proj
	updateDebugVisual(id, proj.position)

	-- Build spawn payload (recipe-only; no particles/trails data). Clients will run deterministic sim.
	local recipe = {
		movementType = proj.movementType,
		gravity = proj.gravity,
		lifetime = proj.lifetime,
		radius = proj.radius,
		pierce = proj.pierce,
		movementParams = proj.movementParams,
		extraData = proj.extraData,
		skillName = proj.skillName,
		launchSpeed = proj.launchSpeed,
		guidance = sanitizeGuidance(proj.guidance),
		guidanceStack = sanitizeGuidanceStack(proj.guidanceStack),
	}

	local payload = {
		phase = "spawn",
		id = id,
		template = proj.templateKey,
		cframe = params.cframe,
		velocity = proj.velocity,
		token = proj.token,
		recipe = recipe,
		skillName = proj.skillName,
		t = os.clock(),
		seq = proj.seq,
		initial = { position = proj.startPosition, velocity = proj.startVelocity, seq = proj.seq },
		ownerEntityId = proj.ownerEntityId,
		attach = proj.attach,
	}

	broadcastPayload(proj.startPosition, proj.notifyRadius, payload)

	return id
end

function ProjectileService.destroyProjectile(id: number, reason: string?)
	local proj = activeProjectiles[id]
	if not proj then
		return
	end
	if proj.onDestroy then
		pcall(proj.onDestroy, proj)
	end
	activeProjectiles[id] = nil
	destroyDebugVisual(id)
	local payload = { phase = "destroy", id = id, t = os.clock(), reason = reason }
	broadcastPayload(proj.position, proj.notifyRadius, payload)
end

local function emitHit(proj: any, pos: Vector3, hitResult: any?)
	-- Compute a CFrame for the impact so clients can orient FX correctly.
	local hitCFrame: CFrame? = nil
	if hitResult and hitResult.Position then
		local normal = hitResult.Normal
			or (proj.velocity and proj.velocity.Magnitude > 0 and -proj.velocity.Unit)
			or Vector3.new(0, 1, 0)
		hitCFrame = CFrame.lookAt(hitResult.Position, hitResult.Position + normal)
	else
		if proj.velocity and proj.velocity.Magnitude > 0 then
			hitCFrame = CFrame.lookAt(pos, pos + proj.velocity.Unit)
		else
			hitCFrame = CFrame.new(pos)
		end
	end

	local payload =
		{ phase = "hit", id = proj.id, t = os.clock(), pos = pos, hitCFrame = hitCFrame, extraData = proj.extraData }
	broadcastPayload(pos, proj.notifyRadius, payload)
end

RunService.Heartbeat:Connect(function(dt: number)
	if not DebugConfig.isEnabled("projectiles") and next(debugVisuals) ~= nil then
		for id in pairs(debugVisuals) do
			destroyDebugVisual(id)
		end
	end
	for id, proj in pairs(activeProjectiles) do
		local prevPos = proj.position
		proj.age += dt

		local speedForSteps = proj.velocity.Magnitude
		if speedForSteps <= 1e-3 and type(proj.launchSpeed) == "number" then
			speedForSteps = proj.launchSpeed
		end
		local steps = math.max(1, math.ceil((speedForSteps * dt) / math.max(0.5, proj.radius or 1)))
		local stepDt = dt / steps
		local baseAge = proj.age - dt
		local mvFormula = nil
		if proj.movementParams ~= nil then
			mvFormula = movementTypes[proj.movementType]
		end
		local guidanceStack = proj.guidanceStack
		local stop = false
		for _ = 1, steps do
			if guidanceStack and #guidanceStack > 0 then
				local t = baseAge + stepDt
				baseAge = t
				local basePos, baseVel = Trajectory.computeBase(
					proj.movementType or "linear",
					t,
					proj.startPosition,
					proj.startVelocity,
					proj.movementParams
				)
				local anyInfluence = false
				local currentVel = proj.velocity
				local nextVel = baseVel
				for _, g in ipairs(guidanceStack) do
					if g.kind == "homing" then
						if g.maxHomingTime and proj.age >= g.maxHomingTime then
							continue
						end
						local targetId = g.targetEntityId
						if (not targetId or targetId == "") and g.reacquire then
							targetId = selectHomingTarget(proj, g)
							if targetId then
								g.targetEntityId = targetId
							end
						end
						local target = (targetId and Registrar.getEntityById(targetId)) or nil
						if (not target or not target.Parent) and g.reacquire then
							local newId = selectHomingTarget(proj, g)
							if newId then
								g.targetEntityId = newId
								target = Registrar.getEntityById(newId)
							end
						end
						if target and target.Parent then
							local root = getEntityRoot(target)
							if root then
								local guidedVel, weight =
									Guidance.applyHoming(nextVel, currentVel, proj.position, root.Position, stepDt, g, proj.launchSpeed)
								nextVel = guidedVel
								currentVel = guidedVel
								if weight > 0 then
									anyInfluence = true
								end
							end
						end
					end
				end
				if anyInfluence then
					proj.velocity = nextVel
					proj.position = proj.position + nextVel * stepDt
				else
					proj.velocity = baseVel
					proj.position = basePos
				end
				if
					not proj._ended
					and proj.movementParams
					and proj.movementParams.endOnArrival
					and type(proj.movementParams.flightTime) == "number"
					and t >= proj.movementParams.flightTime
				then
					proj._ended = true
					if proj.onEnd then
						pcall(proj.onEnd, proj, proj.position)
					end
					emitHit(proj, proj.position, nil)
					ProjectileService.destroyProjectile(id, "arrived")
					stop = true
				end
				if stop then
					break
				end
			elseif mvFormula then
				local t = baseAge + stepDt
				baseAge = t
				local nextPos = mvFormula(t, proj.startPosition, proj.startVelocity, proj.movementParams)
				if typeof(nextPos) == "Vector3" then
					proj.velocity = (nextPos - proj.position) / stepDt
					proj.position = nextPos
				end
				if
					not proj._ended
					and proj.movementParams
					and proj.movementParams.endOnArrival
					and type(proj.movementParams.flightTime) == "number"
					and t >= proj.movementParams.flightTime
				then
					proj._ended = true
					if proj.onEnd then
						pcall(proj.onEnd, proj, proj.position)
					end
					emitHit(proj, proj.position, nil)
					ProjectileService.destroyProjectile(id, "arrived")
					stop = true
				end
				if stop then
					break
				end
			else
				updateGuidance(proj, stepDt)
				if proj.gravity then
					proj.velocity = proj.velocity + Vector3.new(0, proj.gravity * stepDt, 0)
				end
				proj.position = proj.position + proj.velocity * stepDt
			end

			if proj.onUpdate then
				pcall(proj.onUpdate, proj, stepDt)
			end

			local rayDir = proj.position - prevPos
			if rayDir.Magnitude > 0 then
				local ignoreList = {}
				if proj.owner and typeof(proj.owner) == "Instance" then
					table.insert(ignoreList, proj.owner)
				end
				if proj.radius and proj.radius > 0 then
					local overlap = Workspace:GetPartBoundsInRadius(proj.position, proj.radius, nil)
					for _, part in ipairs(overlap) do
						if not table.find(ignoreList, part) and not proj._alreadyHit[part] then
							local hitEntity = resolveEntityFromPart(part)
							if not hitEntity then
								continue
							end
							local targetFaction = EntityUtils.getFaction(hitEntity)
							if targetFaction ~= proj.faction then
								proj._alreadyHit[part] = true
								local cont = true
								if proj.onHit then
									local ok, ret = pcall(proj.onHit, proj, part, hitEntity, nil)
									if ok and ret == false then
										cont = false
									end
								end
								emitHit(proj, proj.position, nil)
								proj.pierce -= 1
								if proj.pierce <= 0 or not cont then
									ProjectileService.destroyProjectile(id, "hit")
									stop = true
									break
								end
							end
						end
					end
				else
					local rayParams = RaycastParams.new()
					rayParams.FilterType = Enum.RaycastFilterType.Exclude
					rayParams.FilterDescendantsInstances = {}
					if proj.owner and typeof(proj.owner) == "Instance" then
						table.insert(rayParams.FilterDescendantsInstances, proj.owner)
					end
					local result = Workspace:Raycast(prevPos, rayDir, rayParams)
					if result and result.Instance then
						local hitPart = result.Instance
						local hitEntity = resolveEntityFromPart(hitPart)
						if not hitEntity then
							prevPos = proj.position
							continue
						end
						local targetFaction = EntityUtils.getFaction(hitEntity)
						if targetFaction ~= proj.faction then
							if not proj._alreadyHit[hitPart] then
								proj._alreadyHit[hitPart] = true
								local cont = true
								if proj.onHit then
									local ok, ret = pcall(proj.onHit, proj, hitPart, hitEntity, result)
									if ok and ret == false then
										cont = false
									end
								end
								emitHit(proj, result.Position, result)
								proj.pierce -= 1
								if proj.pierce <= 0 or not cont then
									ProjectileService.destroyProjectile(id, "hit")
									stop = true
								end
							end
						end
					end
				end
			end
			prevPos = proj.position
			if stop then
				break
			end
		end
		-- Avoid re-creating debug visuals if projectile was destroyed mid-step.
		if activeProjectiles[id] ~= nil then
			updateDebugVisual(id, proj.position)
			if proj.age >= proj.lifetime then
				ProjectileService.destroyProjectile(id, "timeout")
			end
		end
	end
end)

function ProjectileService.getProjectile(id: number)
	return activeProjectiles[id]
end

function ProjectileService.activateAttachedProjectile(id: number, serverCFrame: CFrame, serverVelocity: Vector3)
	local proj = activeProjectiles[id]
	if not proj then
		return false, "not_found"
	end
	if not proj.attach then
		return false, "not_attached"
	end

	-- Move server-side projectile to the provided serverCFrame/velocity and clear attach state
	proj.startPosition = serverCFrame.Position
	proj.position = proj.startPosition
	-- prefer configured launchSpeed if present to ensure server authoritative speed
	if proj.launchSpeed and type(proj.launchSpeed) == "number" then
		proj.startVelocity = serverCFrame.LookVector * proj.launchSpeed
		proj.velocity = proj.startVelocity
	else
		proj.startVelocity = serverVelocity
		proj.velocity = serverVelocity
	end
	proj.attach = nil
	proj.seq += 1

	local payload =
		{ phase = "shoot", id = id, cframe = serverCFrame, velocity = serverVelocity, t = os.clock(), seq = proj.seq }
	-- Broadcast to nearby clients only (re-use local helper)
	broadcastPayload(proj.position, proj.notifyRadius, payload)
	return true, "ok"
end

return ProjectileService
