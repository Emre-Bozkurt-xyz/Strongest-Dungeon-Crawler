--!strict
-- Spawn-only ProjectileService (clean): server-side logic and spawn-only visual recipes

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local EntityUtils = require(ReplicatedStorage.Shared.EntityUtils)
local ProjectileEvent = require(script.Parent.ProjectileEvent)

local ProjectileService = {}
ProjectileService.__index = ProjectileService

-- Active logical projectiles (server-side only)
local activeProjectiles: { [number]: any } = {}
local nextId = 1

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
	extraData: any?,
	-- server only: if set, server will only notify clients within this radius (studs)
	notifyRadius: number?,
	-- optional attachment info for spawn-and-hold patterns (owner must be a player for client attach)
	attach: {
		ownerUserId: number?,
		partName: string?,
	}?,
}

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
	elseif params.attach and params.attach.ownerUserId then
		local players = game:GetService("Players")
		local owner = players:GetPlayerByUserId(params.attach.ownerUserId)
		if owner and owner.Character then
			local part = owner.Character:FindFirstChild(params.attach.partName, true)
			if part then
				if part:IsA("Attachment") then
					resolvedPos = part.WorldCFrame.Position
				elseif part:IsA("BasePart") then
					resolvedPos = part.Position
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
		skillName = params.skillName,
		launchSpeed = params.launchSpeed,
		movementType = params.movementType or "linear",
		gravity = params.gravity,
		lifetime = params.lifetime or 5,
		age = 0,
		owner = params.owner,
		faction = params.faction or (params.owner and EntityUtils.getFaction(params.owner)) or "Neutral",
		radius = params.radius,
		pierce = params.pierce or 1,
		onHit = params.onHit,
		onUpdate = params.onUpdate,
		onDestroy = params.onDestroy,
		extraData = params.extraData,
		templateKey = params.templateKey or "",
		_alreadyHit = {},
		seq = 1,
		notifyRadius = params.notifyRadius,
		attach = params.attach,
	}

	activeProjectiles[id] = proj

	-- Build spawn payload (recipe-only; no particles/trails data). Clients will run deterministic sim.
	local recipe = {
		movementType = proj.movementType,
		gravity = proj.gravity,
		lifetime = proj.lifetime,
		radius = proj.radius,
		pierce = proj.pierce,
		extraData = proj.extraData,
		skillName = proj.skillName,
		launchSpeed = proj.launchSpeed,
	}

	local ownerUserId: number? = nil
	if proj.owner and typeof(proj.owner) == "Instance" then
		local ok, isPlayer = pcall(function()
			return proj.owner:IsA("Player")
		end)
		if ok and isPlayer then
			-- Users are Players and have UserId
			ownerUserId = (proj.owner :: any).UserId
		end
	end

	local payload = {
		phase = "spawn",
		id = id,
		template = proj.templateKey,
		cframe = params.cframe,
		velocity = proj.velocity,
		recipe = recipe,
		skillName = proj.skillName,
		t = os.clock(),
		seq = proj.seq,
		initial = { position = proj.startPosition, velocity = proj.startVelocity, seq = proj.seq },
		ownerUserId = ownerUserId,
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
	for id, proj in pairs(activeProjectiles) do
		local prevPos = proj.position
		proj.age += dt

		local steps = math.max(1, math.ceil((proj.velocity.Magnitude * dt) / math.max(0.5, proj.radius or 1)))
		local stepDt = dt / steps
		local stop = false
		for _ = 1, steps do
			if proj.gravity then
				proj.velocity = proj.velocity + Vector3.new(0, proj.gravity * stepDt, 0)
			end
			proj.position = proj.position + proj.velocity * stepDt

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
							local hitEntity = part.Parent
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
						local hitEntity = hitPart.Parent
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

		if proj and proj.age >= proj.lifetime then
			ProjectileService.destroyProjectile(id, "timeout")
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
