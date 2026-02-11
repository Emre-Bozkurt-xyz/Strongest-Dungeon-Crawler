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
local CollectionService = game:GetService("CollectionService")

local Networking = require(ReplicatedStorage.Shared.Networking)
local Entities = require(ReplicatedStorage.Shared.Utils.Entities)
local FXPlayer = require(script.Parent.Parent.fx.FXPlayer)
local AnimationCoordinator = require(script.Parent.Parent.Animation.AnimationCoordinator)
local ClientSpec = require(ReplicatedStorage.Shared.skills.ClientSpec)
local DebugConfig = require(ReplicatedStorage.Shared.Debug.DebugConfig)
local EntityUtils = require(ReplicatedStorage.Shared.EntityUtils)
local Registrar = require(script.Parent.Registrar)
local Trajectory = require(ReplicatedStorage.Shared.Projectiles.Trajectory)
local Guidance = require(ReplicatedStorage.Shared.Projectiles.Guidance)

local dispatcher = Networking.client()
local dispatcherAny = dispatcher :: any
-- Note: Channel setup handled by ChannelRegistry.load() in init.client.luau

local ProjectilesClient = {}

local function debugLog(...: any)
	if DebugConfig.isEnabled("projectiles") then
		print("[ProjectilesClient]", ...)
	end
end

local function getLocalEntityId(): string?
	return Registrar.getLocalEntityId()
end

-- Map of local attach tokens by partName for the local player
local attachTokens: { [string]: string } = {}
local predictedByToken: { [string]: any } = {}
local nextPredictedId = -1

local debugVisuals: { [number]: BasePart } = {}
local debugFolder: Folder? = nil

local function getDebugFolder(): Folder
	if debugFolder and debugFolder.Parent then
		return debugFolder
	end
	local folder = Workspace:FindFirstChild("_ProjectileDebugClient")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "_ProjectileDebugClient"
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
		part.Name = "ProjectileDebugClient"
		part.Size = Vector3.new(0.25, 0.25, 0.25)
		part.Shape = Enum.PartType.Ball
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Material = Enum.Material.Neon
		part.Color = Color3.fromRGB(140, 255, 170)
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

local function clearDebugVisuals()
	for id, part in pairs(debugVisuals) do
		debugVisuals[id] = nil
		if part then
			part:Destroy()
		end
	end
end

-- RequestShoot helper exposed on the module so other code (and animation handlers) can
-- request the server to activate an attached projectile.
function ProjectilesClient.requestShoot(projId: number, localCFrame: CFrame?, localVelocity: Vector3?)
	local payload = {
		projId = projId,
		localCFrame = localCFrame,
		localVelocity = localVelocity,
		clientTs = os.clock(),
	}
	debugLog("RequestShoot", payload)
	dispatcherAny:intent("RequestShoot", payload)
end

-- Pools and active visuals
local pools: { [string]: { Instance } } = {}
local visuals: { [number]: any } = {}
local staticVisuals: { [number]: { inst: Instance, templateKey: string } } = {}
local nextStaticId = -1000000

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

local function applyCFrame(inst: Instance, cf: CFrame)
	if inst:IsA("Model") then
		local primary = inst.PrimaryPart
		if primary then
			primary.CFrame = cf
		else
			pcall(inst.PivotTo, inst, cf)
		end
	elseif inst:IsA("BasePart") then
		inst.CFrame = cf
	end
end

local destroyVisualEntry: (number) -> ()

local function resolveEntityFromPart(part: BasePart?): Model?
	local current: Instance? = part
	while current do
		if current:IsA("Model") and Registrar.getEntityId(current) then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function trySpeculativeImpact(entry: any, prevPos: Vector3, pos: Vector3, vel: Vector3)
	if entry._specHit then
		return
	end
	local recipe = entry.recipe
	if not (recipe and recipe.speculativeImpact) then
		return
	end
	local localEntityId = getLocalEntityId()
	if not localEntityId then
		return
	end
	if not entry.attachHint or entry.attachHint.ownerEntityId ~= localEntityId then
		return
	end
	local impactKey: string = "Impact"
	if recipe.extraData and type(recipe.extraData.impactKey) == "string" then
		impactKey = recipe.extraData.impactKey
	end
	local ignoreList: { Instance } = {}
	local lpChar = Players.LocalPlayer and Players.LocalPlayer.Character
	if lpChar then
		table.insert(ignoreList, lpChar)
	end
	if VIS_ROOT then
		table.insert(ignoreList, VIS_ROOT)
	end

	local radius = recipe.radius
	if radius and radius > 0 then
		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = ignoreList
		local parts = Workspace:GetPartBoundsInRadius(pos, radius, params)
		for _, part in ipairs(parts) do
			local model = resolveEntityFromPart(part)
			if model then
				local entityId = Registrar.getEntityId(model)
				if entityId and entityId ~= localEntityId then
					local forward = if vel.Magnitude > 0.001 then vel.Unit else Vector3.new(0, 0, 1)
					local cf = CFrame.lookAt(pos, pos + forward)
					FXPlayer.playAt(impactKey, cf)
					entry._specHit = true
					entry._specHitAt = os.clock()
					if entry.remainingPierce and entry.remainingPierce > 0 then
						entry.remainingPierce -= 1
						if entry.remainingPierce <= 0 then
							if destroyVisualEntry then
								destroyVisualEntry(entry.id)
							end
						end
					end
					break
				end
			end
		end
	else
		local dir = pos - prevPos
		if dir.Magnitude > 0.001 then
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = ignoreList
			local result = Workspace:Raycast(prevPos, dir, params)
			if result and result.Instance then
				local model = resolveEntityFromPart(result.Instance)
				if model then
					local entityId = Registrar.getEntityId(model)
					if entityId and entityId ~= localEntityId then
						local forward = if vel.Magnitude > 0.001 then vel.Unit else Vector3.new(0, 0, 1)
						local cf = CFrame.lookAt(result.Position, result.Position + forward)
						FXPlayer.playAt(impactKey, cf)
						entry._specHit = true
						entry._specHitAt = os.clock()
						if entry.remainingPierce and entry.remainingPierce > 0 then
							entry.remainingPierce -= 1
							if entry.remainingPierce <= 0 then
								if destroyVisualEntry then
									destroyVisualEntry(entry.id)
								end
							end
						end
					end
				end
			end
		end
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

movementTypes["cascading"] = {
	pos = function(t: number, p0: Vector3, _v0: Vector3, params: any)
		return Trajectory.cascadingPos(t, p0, params)
	end,
	vel = function(t: number, p0: Vector3, _v0: Vector3, params: any)
		return Trajectory.cascadingVel(t, p0, params, 1 / 60)
	end,
}

movementTypes["arc"] = {
	pos = function(t: number, p0: Vector3, _v0: Vector3, params: any)
		return Trajectory.arcPos(t, p0, params)
	end,
	vel = function(t: number, p0: Vector3, _v0: Vector3, params: any)
		return Trajectory.arcVel(t, p0, params, 1 / 60)
	end,
}

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

local function selectHomingTargetClient(entry: any, g: any?): string?
	local guide = g or entry.guidance
	if not guide or guide.kind ~= "homing" then
		return nil
	end
	local casterModel = Players.LocalPlayer and Players.LocalPlayer.Character
	local casterFaction = EntityUtils.getFaction(casterModel)
	local maxRange = guide.maxRange
	local tag = guide.targetTag
	local relation = guide.factionRelation or "enemy"
	local bestId = nil
	local bestDist = nil
	for _, entity in ipairs(Entities.getAllEntities()) do
		if entity and entity.Parent then
			if casterModel and entity == casterModel then
				continue
			end
			if tag and not CollectionService:HasTag(entity, tag) then
				continue
			end
			local targetFaction = EntityUtils.getFaction(entity)
			if not isRelationMatch(casterFaction, targetFaction, relation) then
				continue
			end
			local root = entity.PrimaryPart or entity:FindFirstChild("HumanoidRootPart")
			if root then
				local dist = (root.Position - entry.position).Magnitude
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

movementTypes["homing"] = {
	update = function(entry: any, dt: number)
		local guidance = entry.guidance
		if guidance and guidance.maxHomingTime and entry.age and entry.age >= guidance.maxHomingTime then
			entry.position = entry.position + entry.velocity * dt
			return
		end
		local targetId = guidance and guidance.targetEntityId
		if (not targetId or targetId == "") and guidance and guidance.reacquire then
			targetId = selectHomingTargetClient(entry, guidance)
			if targetId then
				guidance.targetEntityId = targetId
			end
		end
		local target = (targetId and Entities.getEntityById(targetId)) or nil
		if not target or not target.Parent then
			if guidance and guidance.reacquire then
				local newId = selectHomingTargetClient(entry, guidance)
				if newId then
					guidance.targetEntityId = newId
					target = Entities.getEntityById(newId)
				end
			end
		end
		if not target or not target.Parent then
			entry.position = entry.position + entry.velocity * dt
			return
		end
		local root = target.PrimaryPart or target:FindFirstChild("HumanoidRootPart")
		if not root then
			entry.position = entry.position + entry.velocity * dt
			return
		end
		local desiredDir = root.Position - entry.position
		if desiredDir.Magnitude <= 1e-4 then
			entry.position = entry.position + entry.velocity * dt
			return
		end
		local speed = entry.velocity.Magnitude
		if speed <= 1e-4 then
			speed = (entry.recipe and entry.recipe.launchSpeed) or entry.startVel.Magnitude or 30
		end
		local turnRate = (guidance and guidance.turnRate) or 360
		local maxTurnRad = math.rad(turnRate) * dt
		local curDir = if entry.velocity.Magnitude > 1e-4 then entry.velocity.Unit else desiredDir.Unit
		local newDir = rotateTowards(curDir, desiredDir, maxTurnRad)
		entry.velocity = newDir * speed
		entry.position = entry.position + entry.velocity * dt
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
	applyCFrame(inst, cframe)

	local entry = {
		id = id,
		inst = inst,
		templateKey = templateKey,
		recipe = recipe or { movementType = "linear" },
		startCFrame = cframe,
		startPos = cframe.Position,
		startVel = velocity or Vector3.new(),
		position = cframe.Position,
		velocity = velocity or Vector3.new(),
		simTime = 0,
		age = 0,
		lifetime = (recipe and recipe.lifetime) or 5,
		attached = false,
		attachTarget = nil,
		attachOffset = nil,
		attachHint = nil,
		guidance = recipe and recipe.guidance or nil,
		guidanceStack = recipe and recipe.guidanceStack or nil,
		remainingPierce = (recipe and recipe.pierce) or 1,
		predicted = false,
		predictedToken = nil,
		pendingRelease = nil,
		_specHit = false,
		_specHitAt = nil,
	}

	-- attach hint: only attach when the spawn was for this local player
	if attach and attach.ownerEntityId and attach.partName then
		local lp = Players.LocalPlayer
		local localEntityId = getLocalEntityId()
		if lp and localEntityId and localEntityId == attach.ownerEntityId and lp.Character then
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
			local localEntityId = getLocalEntityId()
			if lp and attach.ownerEntityId and localEntityId == attach.ownerEntityId then
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
			local localEntityId = getLocalEntityId()
			if not localEntityId or ctx.ownerEntityId ~= localEntityId then
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
			if entry.id < 0 then
				-- predicted entry with no server id yet; queue release until reconciliation
				entry.pendingRelease = { localCFrame = localCf, localVelocity = localVel }
				debugLog("Queued release; waiting for server id", entry.predictedToken)
			else
				debugLog("Release marker fired", skillName, entry.id, entry.attachHint and entry.attachHint.token)
				ProjectilesClient.requestShoot(entry.id, localCf, localVel)
			end
		end)
		entry._markerDisconnect = disconnect
	end

	visuals[id] = entry
	return entry
end

destroyVisualEntry = function(id: number)
	local entry = visuals[id]
	if not entry then
		return
	end
	destroyDebugVisual(id)
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
	if entry.predictedToken and predictedByToken[entry.predictedToken] == entry then
		predictedByToken[entry.predictedToken] = nil
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

function ProjectilesClient.spawnPredicted(skillName: string, projectileSpec: any, token: string?): any
	if type(projectileSpec) ~= "table" or not projectileSpec.templateKey then
		return nil
	end
	if not token or token == "" then
		return nil
	end
	local localEntityId = getLocalEntityId()
	if not localEntityId then
		return nil
	end

	local templateKey = projectileSpec.templateKey
	local attachPart = projectileSpec.attachPart or projectileSpec.partName or "FX_Hand_R"
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	if not character then
		return nil
	end
	local attachTarget = character:FindFirstChild(attachPart, true)
	if not attachTarget then
		attachPart = "RightHand"
		attachTarget = character:FindFirstChild(attachPart, true)
	end
	if not attachTarget then
		attachPart = "Right Arm"
		attachTarget = character:FindFirstChild(attachPart, true)
	end
	if not attachTarget then
		attachPart = "HumanoidRootPart"
		attachTarget = character:FindFirstChild(attachPart, true)
	end
	local startCFrame = nil
	if attachTarget then
		if attachTarget:IsA("Attachment") then
			startCFrame = attachTarget.WorldCFrame
		elseif attachTarget:IsA("BasePart") then
			startCFrame = attachTarget.CFrame
		end
	end
	if not startCFrame then
		local root = character.PrimaryPart
		if root then
			startCFrame = root.CFrame
		else
			startCFrame = CFrame.new()
		end
	end

	local recipe = {
		movementType = projectileSpec.movementType or "linear",
		gravity = projectileSpec.gravity,
		lifetime = projectileSpec.lifetime or 5,
		radius = projectileSpec.radius,
		pierce = projectileSpec.pierce,
		movementParams = projectileSpec.movementParams,
		extraData = projectileSpec.extraData,
		skillName = skillName,
		launchSpeed = projectileSpec.launchSpeed,
		guidance = projectileSpec.guidance,
		guidanceStack = projectileSpec.guidanceStack,
		speculativeImpact = projectileSpec.speculativeImpact,
	}

	local attach = {
		ownerEntityId = localEntityId,
		partName = attachPart,
		token = token,
	}

	local predictedId = nextPredictedId
	nextPredictedId -= 1
	local entry = createVisualEntry(predictedId, templateKey, startCFrame, Vector3.new(), recipe, attach)
	entry.predicted = true
	entry.predictedToken = token
	predictedByToken[token] = entry
	return entry
end

-- Lightweight static visuals (no simulation). Useful for charge-up rings.
function ProjectilesClient.spawnStaticVisual(templateKey: string, cframe: CFrame): number?
	if not templateKey or templateKey == "" then
		return nil
	end
	local inst = acquireVisual(templateKey)
	if not inst then
		return nil
	end
	inst.Parent = VIS_ROOT
	applyCFrame(inst, cframe)
	local id = nextStaticId
	nextStaticId -= 1
	staticVisuals[id] = { inst = inst, templateKey = templateKey }
	return id
end

function ProjectilesClient.updateStaticVisual(id: number, cframe: CFrame)
	local entry = staticVisuals[id]
	if not entry then
		return
	end
	applyCFrame(entry.inst, cframe)
end

function ProjectilesClient.destroyStaticVisual(id: number)
	local entry = staticVisuals[id]
	if not entry then
		return
	end
	staticVisuals[id] = nil
	releaseVisual(entry.templateKey, entry.inst)
end

function ProjectilesClient.clearStaticVisuals()
	for id in pairs(staticVisuals) do
		ProjectilesClient.destroyStaticVisual(id)
	end
end

function ProjectilesClient.spawnPredictedReleased(
	skillName: string,
	projectileSpec: any,
	token: string?,
	startCFrame: CFrame?,
	startVelocity: Vector3?
): any
	if type(projectileSpec) ~= "table" or not projectileSpec.templateKey then
		return nil
	end
	if not token or token == "" then
		return nil
	end

	local templateKey = projectileSpec.templateKey
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	local spawnCf = startCFrame
	if not spawnCf then
		local attachPart = projectileSpec.attachPart or projectileSpec.partName or "FX_Hand_R"
		local attachTarget = character and character:FindFirstChild(attachPart, true)
		if not attachTarget and character then
			attachTarget = character:FindFirstChild("RightHand", true)
		end
		if not attachTarget and character then
			attachTarget = character:FindFirstChild("Right Arm", true)
		end
		if not attachTarget and character then
			attachTarget = character:FindFirstChild("HumanoidRootPart", true)
		end
		if attachTarget then
			if attachTarget:IsA("Attachment") then
				spawnCf = attachTarget.WorldCFrame
			elseif attachTarget:IsA("BasePart") then
				spawnCf = attachTarget.CFrame
			end
		end
	end
	if not spawnCf then
		local root = character and character.PrimaryPart
		if root then
			spawnCf = root.CFrame
		else
			spawnCf = CFrame.new()
		end
	end

	local recipe = {
		movementType = projectileSpec.movementType or "linear",
		gravity = projectileSpec.gravity,
		lifetime = projectileSpec.lifetime or 5,
		radius = projectileSpec.radius,
		pierce = projectileSpec.pierce,
		movementParams = projectileSpec.movementParams,
		extraData = projectileSpec.extraData,
		skillName = skillName,
		launchSpeed = projectileSpec.launchSpeed,
		guidance = projectileSpec.guidance,
		guidanceStack = projectileSpec.guidanceStack,
		speculativeImpact = projectileSpec.speculativeImpact,
	}

	local launchSpeed = projectileSpec.launchSpeed or 0
	local startVel = startVelocity
	if not startVel then
		startVel = spawnCf.LookVector * launchSpeed
	end

	local predictedId = nextPredictedId
	nextPredictedId -= 1
	local entry = createVisualEntry(predictedId, templateKey, spawnCf, startVel, recipe, nil)
	entry.predicted = true
	entry.predictedToken = token
	predictedByToken[token] = entry
	return entry
end

function ProjectilesClient.cancelPredicted(token: string?)
	if not token then
		return
	end
	local entry = predictedByToken[token]
	if entry then
		predictedByToken[token] = nil
		destroyVisualEntry(entry.id)
	end
end

-- Render loop: deterministic sim per visual
local lastTime = os.clock()
RunService.RenderStepped:Connect(function()
	local now = os.clock()
	local dt = now - lastTime
	lastTime = now
	local debugEnabled = DebugConfig.isEnabled("projectiles")
	if not debugEnabled and next(debugVisuals) ~= nil then
		clearDebugVisuals()
	end
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
			if debugEnabled then
				updateDebugVisual(entry.id, finalCf.Position)
			end
		else
			local prevPos = entry.position
			entry.simTime = entry.simTime + dt
			entry.age = entry.age + dt
			local mv = movementTypes[entry.recipe.movementType or "linear"]
			local guidanceStack = entry.guidanceStack
			local pos: Vector3
			local vel: Vector3 = Vector3.new()
			if guidanceStack and #guidanceStack > 0 then
				local basePos, baseVel = Trajectory.computeBase(
					entry.recipe.movementType or "linear",
					entry.simTime,
					entry.startPos,
					entry.startVel,
					entry.recipe
				)
				local anyInfluence = false
				local currentVel = entry.velocity
				local nextVel = baseVel
				for _, g in ipairs(guidanceStack) do
					if g.kind == "homing" then
						if g.maxHomingTime and entry.age and entry.age >= g.maxHomingTime then
							continue
						end
						local targetId = g.targetEntityId
						if (not targetId or targetId == "") and g.reacquire then
							targetId = selectHomingTargetClient(entry, g)
							if targetId then
								g.targetEntityId = targetId
							end
						end
						local target = (targetId and Entities.getEntityById(targetId)) or nil
						if (not target or not target.Parent) and g.reacquire then
							local newId = selectHomingTargetClient(entry, g)
							if newId then
								g.targetEntityId = newId
								target = Entities.getEntityById(newId)
							end
						end
						if target and target.Parent then
							local root = target.PrimaryPart or target:FindFirstChild("HumanoidRootPart")
							if root then
								local guidedVel, weight = Guidance.applyHoming(
									nextVel,
									currentVel,
									entry.position,
									root.Position,
									dt,
									g,
									entry.recipe.launchSpeed
								)
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
					entry.velocity = nextVel
					entry.position = entry.position + nextVel * dt
				else
					entry.velocity = baseVel
					entry.position = basePos
				end
				pos = entry.position
				vel = entry.velocity
			elseif mv and mv.update then
				mv.update(entry, dt)
				pos = entry.position
				vel = entry.velocity
			elseif mv then
				pos = mv.pos(entry.simTime, entry.startPos, entry.startVel, entry.recipe)
				vel = mv.vel(entry.simTime, entry.startPos, entry.startVel, entry.recipe)
				entry.position = pos
				entry.velocity = vel
			else
				pos = entry.startPos + entry.startVel * entry.simTime
				vel = entry.startVel
				entry.position = pos
				entry.velocity = vel
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

			if debugEnabled then
				updateDebugVisual(entry.id, pos)
			end

			trySpeculativeImpact(entry, prevPos, pos, vel)

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
		local attach = payload.attach
		local token = payload.token or (attach and attach.token)
		if token and predictedByToken[token] then
			local entry = predictedByToken[token]
			predictedByToken[token] = nil
			local oldId = entry.id
			if oldId ~= payload.id then
				visuals[oldId] = nil
				entry.id = payload.id
				visuals[payload.id] = entry
			end
			entry.predicted = false
			entry.attachHint = attach
			if payload.recipe then
				local merged = {}
				if entry.recipe then
					for k, v in pairs(entry.recipe) do
						merged[k] = v
					end
				end
				for k, v in pairs(payload.recipe) do
					merged[k] = v
				end
				entry.recipe = merged
			end
			entry.guidance = entry.recipe and entry.recipe.guidance or entry.guidance
			entry.guidanceStack = entry.recipe and entry.recipe.guidanceStack or entry.guidanceStack
			entry.lifetime = (entry.recipe and entry.recipe.lifetime) or entry.lifetime
			if entry.remainingPierce == nil then
				entry.remainingPierce = (entry.recipe and entry.recipe.pierce) or 1
			end
			if payload.cframe then
				entry.startCFrame = payload.cframe
				entry.startPos = payload.cframe.Position
				entry.position = payload.cframe.Position
			end
			if payload.velocity then
				entry.startVel = payload.velocity
				entry.velocity = payload.velocity
			end
			entry.simTime = 0
			entry.age = 0
			if entry.pendingRelease then
				ProjectilesClient.requestShoot(
					payload.id,
					entry.pendingRelease.localCFrame,
					entry.pendingRelease.localVelocity
				)
				entry.pendingRelease = nil
			end
		else
			local id = payload.id
			local template = payload.template or ""
			local cframe = payload.cframe or CFrame.new()
			local velocity = payload.velocity or Vector3.new()
			local recipe = payload.recipe or { movementType = "linear" }
			createVisualEntry(id, template, cframe, velocity, recipe, attach)
		end
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
			local entry = visuals[id]
			local recentSpec = entry and entry._specHitAt and (os.clock() - entry._specHitAt) < 0.25
			if not recentSpec then
				FXPlayer.playAt(impactKey, hitCf)
			end
			if entry and not recentSpec then
				entry._specHit = true
				entry._specHitAt = os.clock()
				if entry.remainingPierce and entry.remainingPierce > 0 then
					entry.remainingPierce -= 1
					if entry.remainingPierce <= 0 then
						destroyVisualEntry(id)
					end
				end
			end
		end
	elseif phase == "shoot" then
		local id = payload.id
		local entry = visuals[id]
		if entry then
			entry.attached = false
			if payload.cframe then
				entry.startCFrame = payload.cframe
				entry.startPos = payload.cframe.Position
				entry.position = payload.cframe.Position
			end
			if payload.velocity then
				entry.startVel = payload.velocity
				entry.velocity = payload.velocity
			end
			entry.simTime = 0
			entry.age = 0
			entry.lifetime = (entry.recipe and entry.recipe.lifetime) or entry.lifetime
		end
	end
end)

dispatcher:on("RequestShootResponse", function(payload: any, _meta: any)
	if type(payload) ~= "table" then
		return
	end
	debugLog("RequestShootResponse", payload)
end)

return ProjectilesClient
