--!strict
-- Deterministic Projectiles Client
-- Spawn-only recipe model: clients create and run visuals locally using deterministic formulas.
--
-- How FX are selected on hit:
--  - Server may populate `recipe.extraData` on spawn with small descriptors (e.g. { impactKey = "ManaBallImpact" }).
--  - Server-side `onHit` can mutate `proj.extraData` before the service emits a hit payload.
--  - The hit payload includes `extraData` and `hitCFrame` (orientation); the client prefers those fields when playing FX.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local Networking = require(ReplicatedStorage.Shared.Networking)
local FXPlayer = require(script.Parent.Parent.fx.FXPlayer)
local AnimationCoordinator = require(script.Parent.Parent.Animation.AnimationCoordinator)
local ClientSpec = require(ReplicatedStorage.Shared.skills.ClientSpec)

local dispatcher = Networking.client()
local dispatcherAny = dispatcher :: any
-- Note: Channel setup handled by ChannelRegistry.load() in init.client.luau

local ProjectilesClient = {}

-- Map of local attach tokens by partName for the local player
local attachTokens: { [string]: string } = {}

-- RequestShoot helper exposed on the module so other code (and animation handlers) can
-- request the server to activate an attached projectile.
function ProjectilesClient.requestShoot(projId: number, localCFrame: CFrame?, localVelocity: Vector3?)
	local payload = {
		projId = projId,
		localCFrame = localCFrame,
		localVelocity = localVelocity,
		clientTs = os.clock(),
	}
	dispatcherAny:intent("RequestShoot", payload)
end

-- Pools and active visuals
local pools: { [string]: { Instance } } = {}
local visuals: { [number]: any } = {}

local VIS_ROOT = Workspace:FindFirstChild("Projectiles")
if not VIS_ROOT then
	VIS_ROOT = Instance.new("Folder")
	VIS_ROOT.Name = "Projectiles"
	VIS_ROOT.Parent = Workspace
end

local function acquireVisual(templateKey: string)
	pools[templateKey] = pools[templateKey] or {}
	local pool = pools[templateKey]
	if #pool > 0 then
		return table.remove(pool)
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local projFolder = assets and assets:FindFirstChild("Projectiles")
	if projFolder then
		local tpl = projFolder:FindFirstChild(templateKey)
		if tpl then
			local clone = tpl:Clone()
			if clone:IsA("Model") then
				local primary = clone.PrimaryPart
				if primary then
					primary.Anchored = true
					primary.CanCollide = false
				end
			elseif clone:IsA("BasePart") then
				clone.Anchored = true
				clone.CanCollide = false
			end
			return clone
		end
	end
	local fallback = Instance.new("Part")
	fallback.Size = Vector3.new(0.2, 0.2, 0.6)
	fallback.Anchored = true
	fallback.CanCollide = false
	fallback.Name = "ProjectileFallback"
	return fallback
end

local function releaseVisual(templateKey: string, inst: Instance)
	if inst then
		inst.Parent = nil
		pools[templateKey] = pools[templateKey] or {}
		table.insert(pools[templateKey], inst)
	end
end

-- Movement formulas (mirror server closed-form). Keep simple; can be extended.
local movementTypes: { [string]: any } = {}
movementTypes["linear"] = {
	pos = function(t: number, p0: Vector3, v0: Vector3, _params: any)
		return p0 + v0 * t
	end,
	vel = function(_t: number, _p0: Vector3, v0: Vector3, _params: any)
		return v0
	end,
}
movementTypes["parabolic"] = {
	pos = function(t: number, p0: Vector3, v0: Vector3, params: any)
		local g = (params and params.gravity) or -Workspace.Gravity
		return p0 + v0 * t + Vector3.new(0, 0.5 * g * t * t, 0)
	end,
	vel = function(_t: number, _p0: Vector3, v0: Vector3, params: any)
		local g = (params and params.gravity) or -Workspace.Gravity
		return v0 + Vector3.new(0, g * _t, 0)
	end,
}

local function createVisualEntry(
	id: number,
	templateKey: string,
	cframe: CFrame,
	velocity: Vector3,
	recipe: any,
	attach: any
)
	local inst = acquireVisual(templateKey or "")
	assert(inst, "acquireVisual returned nil")
	inst.Parent = VIS_ROOT
	if inst:IsA("Model") then
		local primary = inst.PrimaryPart
		if primary then
			primary.CFrame = cframe
		else
			pcall(inst.PivotTo, inst, cframe)
		end
	elseif inst:IsA("BasePart") then
		inst.CFrame = cframe
	end

	local entry = {
		id = id,
		inst = inst,
		templateKey = templateKey,
		recipe = recipe or { movementType = "linear" },
		startCFrame = cframe,
		startPos = cframe.Position,
		startVel = velocity or Vector3.new(),
		simTime = 0,
		age = 0,
		lifetime = (recipe and recipe.lifetime) or 5,
		attached = false,
		attachTarget = nil,
		attachOffset = nil,
		attachHint = nil,
	}

	-- attach hint: only attach when the spawn was for this local player
	if attach and attach.ownerUserId and attach.partName then
		local lp = Players.LocalPlayer
		if lp and lp.UserId == attach.ownerUserId and lp.Character then
			-- support both BasePart and Attachment attachments in the character
			local target = lp.Character:FindFirstChild(attach.partName, true)
			if target then
				if target:IsA("BasePart") then
					entry.attached = true
					entry.attachTarget = target
					entry.attachOffset = target.CFrame:Inverse() * cframe
				elseif target:IsA("Attachment") then
					entry.attached = true
					entry.attachTarget = target
					-- use the attachment's WorldCFrame for offsets
					entry.attachOffset = target.WorldCFrame:Inverse() * cframe
				end
			end
		end
	end

	-- preserve original attach hint for token/owner matching when handling release markers
	if attach then
		-- if the server didn't provide a token for this attach, generate one locally so
		-- we can disambiguate release markers and match animation tokens.
		if not attach.token then
			local lp = Players.LocalPlayer
			if lp and attach.ownerUserId and lp.UserId == attach.ownerUserId then
				attach.token = HttpService:GenerateGUID(false)
				-- remember locally so SkillsClient can look it up when playing animations
				attachTokens[attach.partName] = attach.token
			end
		end
		entry.attachHint = attach
	end

	-- If attached and the recipe names a skill, subscribe to that skill's release marker
	-- so the local owner can trigger a local release and send a RequestShoot intent.
	if entry.attached and entry.recipe and type(entry.recipe.skillName) == "string" then
		local skillName = entry.recipe.skillName
		-- Determine release marker: prefer per-spawn override, else check ClientSpec.fx.release for the skill,
		-- otherwise fall back to literal "release".
		local releaseMarker = nil
		if entry.recipe and entry.recipe.extraData and type(entry.recipe.extraData.releaseMarker) == "string" then
			releaseMarker = entry.recipe.extraData.releaseMarker
		else
			local sname = entry.recipe and entry.recipe.skillName
			if type(sname) == "string" then
				local spec = ClientSpec[sname]
				if spec and spec.fx and type(spec.fx.release) == "string" then
					releaseMarker = spec.fx.release
				end
			end
		end
		if not releaseMarker then
			releaseMarker = "release"
		end
		local disconnect = AnimationCoordinator.onSkillMarker(skillName, releaseMarker, function(ctx)
			local lp = Players.LocalPlayer
			if not lp then
				return
			end
			-- only the local owner should trigger the request
			if ctx.ownerUserId ~= lp.UserId then
				return
			end
			-- token match if provided
			if entry.attachHint and entry.attachHint.token and ctx.token ~= entry.attachHint.token then
				return
			end
			-- compute local launch CFrame from attachTarget and stored offset
			local localCf = nil
			if entry.attachTarget then
				if entry.attachTarget:IsA("Attachment") then
					localCf = entry.attachTarget.WorldCFrame * (entry.attachOffset or CFrame.new())
				else
					localCf = entry.attachTarget.CFrame * (entry.attachOffset or CFrame.new())
				end
			else
				localCf = (lp.Character and lp.Character.PrimaryPart and lp.Character.PrimaryPart.CFrame)
					or entry.startCFrame
			end
			local launchSpeed = (entry.recipe and entry.recipe.launchSpeed) or entry.startVel.Magnitude or 0
			local localVel = (localCf and localCf.LookVector and localCf.LookVector * launchSpeed) or entry.startVel
			-- locally un-attach and start sim immediately for responsiveness
			entry.attached = false
			entry.startCFrame = localCf
			entry.startPos = localCf.Position
			entry.startVel = localVel
			entry.simTime = 0
			entry.age = 0
			-- send a request to the server to activate the authoritative projectile
			ProjectilesClient.requestShoot(entry.id, localCf, localVel)
		end)
		entry._markerDisconnect = disconnect
	end

	visuals[id] = entry
	return entry
end

local function destroyVisualEntry(id: number)
	local entry = visuals[id]
	if not entry then
		return
	end
	local inst = entry.inst
	-- cleanup any marker subscription
	if entry._markerDisconnect then
		pcall(entry._markerDisconnect)
		entry._markerDisconnect = nil
	end
	-- cleanup any attach token mapping for the local player
	if entry.attachHint and entry.attachHint.partName and entry.attachHint.token then
		local pn = entry.attachHint.partName
		if attachTokens[pn] == entry.attachHint.token then
			attachTokens[pn] = nil
		end
	end
	visuals[id] = nil
	releaseVisual(entry.templateKey or "", inst)
end

-- Return the locally-generated attach token for a given partName (if any).
function ProjectilesClient.getAttachToken(partName: string): string?
	if not partName then
		return nil
	end
	return attachTokens[partName]
end

-- Render loop: deterministic sim per visual
local lastTime = os.clock()
RunService.RenderStepped:Connect(function()
	local now = os.clock()
	local dt = now - lastTime
	lastTime = now
	for _, entry in pairs(visuals) do
		if entry.attached and entry.attachTarget and entry.attachTarget.Parent then
			local targetCf
			if entry.attachTarget:IsA("Attachment") then
				targetCf = entry.attachTarget.WorldCFrame
			else
				targetCf = entry.attachTarget.CFrame
			end
			local finalCf = targetCf * (entry.attachOffset or CFrame.new())
			if entry.inst:IsA("Model") then
				local primary = entry.inst.PrimaryPart
				if primary then
					primary.CFrame = finalCf
				else
					pcall(entry.inst.PivotTo, entry.inst, finalCf)
				end
			elseif entry.inst:IsA("BasePart") then
				entry.inst.CFrame = finalCf
			end

			-- Client helper exists at module scope: ProjectilesClient.requestShoot
		else
			entry.simTime = entry.simTime + dt
			entry.age = entry.age + dt
			local mv = movementTypes[entry.recipe.movementType or "linear"]
			local pos: Vector3
			local vel: Vector3 = Vector3.new()
			if mv then
				pos = mv.pos(entry.simTime, entry.startPos, entry.startVel, entry.recipe)
				vel = mv.vel(entry.simTime, entry.startPos, entry.startVel, entry.recipe)
			else
				pos = entry.startPos + entry.startVel * entry.simTime
				vel = entry.startVel
			end

			local forward = if vel.Magnitude > 0.001 then vel.Unit else Vector3.new(0, 0, 1)
			local cf = CFrame.lookAt(pos, pos + forward)
			if entry.inst:IsA("Model") then
				local primary = entry.inst.PrimaryPart
				if primary then
					primary.CFrame = cf
				else
					pcall(entry.inst.PivotTo, entry.inst, cf)
				end
			elseif entry.inst:IsA("BasePart") then
				entry.inst.CFrame = cf
			end

			if entry.age >= entry.lifetime then
				destroyVisualEntry(entry.id)
			end
		end
	end
end)

-- Networking handler
dispatcher:on("ProjectileEvent", function(payload: any, _meta: any)
	if type(payload) ~= "table" then
		return
	end
	local phase = payload.phase
	if phase == "spawn" then
		local id = payload.id
		local template = payload.template or ""
		local cframe = payload.cframe or CFrame.new()
		local velocity = payload.velocity or Vector3.new()
		local recipe = payload.recipe or { movementType = "linear" }
		createVisualEntry(id, template, cframe, velocity, recipe, payload.attach)
	elseif phase == "destroy" then
		local id = payload.id
		destroyVisualEntry(id)
	elseif phase == "hit" then
		-- Prefer an oriented CFrame if provided by the server, else compose one from pos + direction.
		local id = payload.id
		local hitCf = payload.hitCFrame
		-- Choose an impact key: payload.extraData > spawned recipe extraData > fallback
		local impactKey: string = "Impact"
		if payload.extraData and type(payload.extraData.impactKey) == "string" then
			impactKey = payload.extraData.impactKey
		else
			local entry = visuals[id]
			if
				entry
				and entry.recipe
				and entry.recipe.extraData
				and type(entry.recipe.extraData.impactKey) == "string"
			then
				impactKey = entry.recipe.extraData.impactKey
			end
		end

		if not hitCf then
			local pos = payload.pos
			if pos then
				local dir = payload.velocity or (visuals[id] and visuals[id].startVel) or Vector3.new(0, 0, 1)
				if dir and dir.Magnitude > 0.001 then
					hitCf = CFrame.lookAt(pos, pos + dir.Unit)
				else
					hitCf = CFrame.new(pos)
				end
			end
		end

		if hitCf and impactKey then
			FXPlayer.playAt(impactKey, hitCf)
		end
	elseif phase == "shoot" then
		local id = payload.id
		local entry = visuals[id]
		if entry then
			entry.attached = false
			if payload.cframe then
				entry.startCFrame = payload.cframe
				entry.startPos = payload.cframe.Position
			end
			if payload.velocity then
				entry.startVel = payload.velocity
			end
			entry.simTime = 0
			entry.age = 0
			entry.lifetime = (entry.recipe and entry.recipe.lifetime) or entry.lifetime
		end
	end
end)

return ProjectilesClient
