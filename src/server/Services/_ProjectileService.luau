--!strict
-- ProjectileService: pooled, extensible projectile manager for skills and other systems

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local _Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local EntityUtils = require(ReplicatedStorage.Shared.EntityUtils)
local ProjectileEvent = require(script.Parent.ProjectileEvent)

local UPDATE_INTERVAL = 0.1 -- seconds (10Hz)
local _updateAccum = 0
local SERVER_DEBUG_PROJECTILES = true
local _serverDebugCount = 0

local ProjectileService = {}
ProjectileService.__index = ProjectileService
-- getFaction is now in EntityUtils

-- Pooling and active projectiles
local activeProjectiles: { [number]: any } = {}
local nextId = 1

-- Movement types registry
local movementTypes: { [string]: (dt: number, proj: any) -> () } = {}

-- Default movement: simple 3D kinematic (linear or parabolic)
movementTypes["linear"] = function(dt, proj)
	proj.position = proj.position + proj.velocity * dt
end
movementTypes["parabolic"] = function(dt, proj)
	proj.velocity = proj.velocity + Vector3.new(0, proj.gravity or -Workspace.Gravity, 0) * dt
	proj.position = proj.position + proj.velocity * dt
end

-- API: Register a custom movement type
function ProjectileService.registerMovementType(name: string, fn: (dt: number, proj: any) -> ())
	movementTypes[name] = fn
end

type SpawnParams = {
	-- server-only logical spawn params
	templateKey: string?, -- short key clients will use to resolve visual template
	template: Instance?, -- optional, only for metadata (NOT cloned or parented by server)
	cframe: CFrame,
	velocity: Vector3,
	gravity: number?,
	movementType: string?,
	lifetime: number?,
	owner: Instance?,
	faction: string?, -- explicit faction/team for this projectile
	radius: number?, -- if set, use thick collision (studs)
	pierce: number?,
	onHit: (proj: any, hitPart: BasePart, hitEntity: Instance, hitResult: RaycastResult?) -> boolean?,
	onUpdate: ((proj: any, dt: number) -> ())?,
	onDestroy: ((proj: any) -> ())?,
	extraData: any?,
}

-- API: Spawn a projectile
--[[
	params: {
		template: Instance,
		cframe: CFrame,
		velocity: Vector3,
		movementType: string?,
		lifetime: number?,
		owner: Instance?,
		faction: string?, -- new: explicit faction/team for this projectile
		radius: number?,  -- new: if set, use thick collision (studs)
		pierce: number?,
		onHit: (proj, hitPart, hitEntity, hitResult) -> boolean?,
		onUpdate: (proj, dt) -> (),
		onDestroy: (proj) -> (),
		extraData: any?,
	}
]]
function ProjectileService.spawnProjectile(params: SpawnParams): number
	assert(
		params and (params.template or params.templateKey) and params.cframe and params.velocity,
		"ProjectileService.spawnProjectile: missing required params (need template or templateKey, cframe, velocity)"
	)

	local id = nextId
	nextId += 1

	local templateKey = params.templateKey or (params.template and (params.template :: Instance).Name) or ""

	local proj = {
		id = id,
		-- server no longer creates or parents visual instances; clients handle visuals
		position = params.cframe.Position,
		lastPos = params.cframe.Position,
		velocity = params.velocity,
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
		templateKey = templateKey,
		_alreadyHit = {},
		-- start seq at 1 so spawn carries an initial authoritative sample
		seq = 1,
	}
	activeProjectiles[id] = proj

	-- Notify clients about the new projectile (clients create visuals locally)
	-- include an initial sample in the spawn payload so clients can seed their buffers
	-- Emit a single atomic spawn message containing an initial authoritative sample.
	-- Clients should seed their buffers from `initial` so they start with the exact
	-- server state at spawn; avoids ordering/re-order issues when sending spawn+update
	-- as separate network messages.
	ProjectileEvent:FireAllClients({
		phase = "spawn",
		id = id,
		template = templateKey,
		cframe = params.cframe,
		velocity = params.velocity,
		lifetime = proj.lifetime,
		radius = proj.radius,
		owner = proj.owner,
		extraData = proj.extraData,
		-- spawn timestamp
		t = os.clock(),
		seq = proj.seq,
		initial = { position = proj.position, velocity = proj.velocity, seq = proj.seq },
	})

	return id
end

-- API: Destroy a projectile early
function ProjectileService.destroyProjectile(id: number)
	local proj = activeProjectiles[id]
	if not proj then
		return
	end
	if proj.onDestroy then
		pcall(proj.onDestroy, proj)
	end
	-- Remove logical projectile from server
	activeProjectiles[id] = nil

	-- Notify clients to remove visual
	ProjectileEvent:FireAllClients({ phase = "destroy", id = id, t = os.clock() })
end

-- Central update loop
RunService.Heartbeat:Connect(function(dt)
	-- Accumulate and decide whether to send updates to clients this frame
	_updateAccum += dt
	local sendUpdates = false
	if _updateAccum >= UPDATE_INTERVAL then
		sendUpdates = true
		_updateAccum = _updateAccum - UPDATE_INTERVAL
	end
	local updates: { any } = {}

	for id, proj in pairs(activeProjectiles) do
		local skip = false
		-- Save last position for raycast
		local prevPos = proj.position

		-- Move
		local moveFn = movementTypes[proj.movementType]
		if moveFn then
			moveFn(dt, proj)
		end

		-- Custom update
		if proj.onUpdate then
			pcall(proj.onUpdate, proj, dt)
		end

		-- Collision/hit detection
		local rayDir = proj.position - prevPos
		if rayDir.Magnitude > 0 then
			local ignoreList = {}
			if proj.owner and typeof(proj.owner) == "Instance" then
				table.insert(ignoreList, proj.owner)
			end

			-- If radius is set, do thick collision (sphere sweep)
			if proj.radius and proj.radius > 0 then
				-- Sample along the path for fast projectiles
				local steps = math.max(1, math.ceil(rayDir.Magnitude / (proj.radius * 1.5)))
				local hitParts: { BasePart } = {}
				for i = 1, steps do
					local alpha = (i - 1) / steps
					local samplePos = prevPos + rayDir * alpha
					local overlap = Workspace:GetPartBoundsInRadius(samplePos, proj.radius, nil)
					for _, part in ipairs(overlap) do
						if not table.find(ignoreList, part) and not proj._alreadyHit[part] then
							table.insert(hitParts, part)
						end
					end
				end
				for _, hitPart in ipairs(hitParts) do
					-- Faction filtering
					local hitEntity = hitPart.Parent
					local targetFaction = EntityUtils.getFaction(hitEntity)
					if targetFaction ~= proj.faction then
						proj._alreadyHit[hitPart] = true
						if proj.onHit then
							local shouldContinue = true
							local ok, ret = pcall(proj.onHit, proj, hitPart, hitEntity, nil)
							if ok and ret == false then
								shouldContinue = false
							end
							proj.pierce -= 1
							if proj.pierce <= 0 or not shouldContinue then
								ProjectileService.destroyProjectile(id)
								skip = true
								break
							end
						else
							ProjectileService.destroyProjectile(id)
							skip = true
							break
						end
					end
				end
			else
				-- Thin raycast (default)
				local rayParams = RaycastParams.new()
				rayParams.FilterType = Enum.RaycastFilterType.Exclude
				rayParams.FilterDescendantsInstances = ignoreList
				local result = Workspace:Raycast(prevPos, rayDir, rayParams)
				if result and result.Instance then
					local hitPart = result.Instance
					local hitEntity = hitPart.Parent
					local targetFaction = EntityUtils.getFaction(hitEntity)
					if targetFaction ~= proj.faction then
						if not proj._alreadyHit[hitPart] then
							proj._alreadyHit[hitPart] = true
							if proj.onHit then
								local shouldContinue = true
								local ok, ret = pcall(proj.onHit, proj, hitPart, hitEntity, result)
								if ok and ret == false then
									shouldContinue = false
								end
								proj.pierce -= 1
								if proj.pierce <= 0 or not shouldContinue then
									ProjectileService.destroyProjectile(id)
									skip = true
								end
							else
								ProjectileService.destroyProjectile(id)
								skip = true
							end
						end
					end
				end
			end
		end

		if skip then
			-- Update lastPos for next frame and skip rest
			if proj and proj.lastPos then
				proj.lastPos = proj.position
			end
		else
			-- Lifetime
			proj.age += dt
			if proj.age >= proj.lifetime then
				ProjectileService.destroyProjectile(id)
			end

			-- Update lastPos for next frame
			proj.lastPos = proj.position

			if sendUpdates then
				proj.seq = (proj.seq or 0) + 1
				table.insert(updates, { id = id, position = proj.position, velocity = proj.velocity, seq = proj.seq })
			end
		end
	end

	if sendUpdates and #updates > 0 then
		local payload = { phase = "update", updates = updates, t = os.clock() }
		-- server-side debug: print a concise summary for the first few batches to diagnose large deltas
		if SERVER_DEBUG_PROJECTILES and _serverDebugCount < 200 then
			_serverDebugCount += 1
			local summary = {}
			for i = 1, math.min(6, #updates) do
				local u = updates[i]
				table.insert(
					summary,
					string.format(
						"id=%d seq=%s pos=(%.2f,%.2f,%.2f)",
						u.id,
						tostring(u.seq or "?"),
						u.position.X,
						u.position.Y,
						u.position.Z
					)
				)
			end
			print(
				"[ProjectileService EMIT] update batch t=",
				payload.t,
				"samples=",
				#updates,
				table.concat(summary, "; ")
			)
		end
		ProjectileEvent:FireAllClients(payload)
	end
end)

-- (Optional) API: Get active projectile by id
function ProjectileService.getProjectile(id: number)
	return activeProjectiles[id]
end

return ProjectileService
