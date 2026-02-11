local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local BaseSkill = require(script.Parent.BaseSkill)
local HeldSkill = require(script.Parent.HeldSkill)
local ProjectilesClient = require(script.Parent.Parent.Parent.Services.ProjectilesClient)
local PatternUtils = require(game:GetService("ReplicatedStorage").Shared.Projectiles.PatternUtils)
local Networking = require(game:GetService("ReplicatedStorage").Shared.Networking)
local Schema = require(game:GetService("ReplicatedStorage").Shared.Debug.Schema)
local Clock = require(game:GetService("ReplicatedStorage").Shared.Time.Clock)
local Registrar = require(script.Parent.Parent.Parent.Services.Registrar)

local dispatcher = Networking.client()

local CascadingManaBallsSkill = {}
CascadingManaBallsSkill.__index = CascadingManaBallsSkill
setmetatable(CascadingManaBallsSkill, HeldSkill)

local function resolveTargetPos(maxRange: number?): Vector3?
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end
	local range = maxRange or 120
	local mousePos = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
	local origin = ray.Origin
	local dir = ray.Direction * range
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = {}
	local lp = Players.LocalPlayer
	if lp and lp.Character then
		table.insert(ignore, lp.Character)
	end
	params.FilterDescendantsInstances = ignore
	local result = Workspace:Raycast(origin, dir, params)
	if result then
		return result.Position
	end
	return origin + dir
end


function CascadingManaBallsSkill.new(name: string?, config: any?)
	local self = setmetatable(HeldSkill.new(name, config), CascadingManaBallsSkill)
	self._predictedTokens = {}
	self._pendingRelease = nil
	self._chargeActive = false
	self._chargeVisuals = {}
	self._chargeConn = nil
	self._chargeTask = nil
	self._chargeSeed = 0
	return self
end

function CascadingManaBallsSkill:_getRootCFrame(): CFrame
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	if character and character.PrimaryPart then
		return character.PrimaryPart.CFrame
	end
	if character then
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			return root.CFrame
		end
	end
	return CFrame.new()
end

function CascadingManaBallsSkill:_startCharge()
	if self._chargeActive then
		return
	end
	self._chargeActive = true
	self._chargeSeed = math.floor((os.clock() * 1e6) % 2147483647)
	self._chargeVisuals = {}

	local chargeCfg = self.config.charge or {}
	local flurryCfg = self.config.flurry or {}
	local maxCount = chargeCfg.maxCount or flurryCfg.count or 30
	local interval = chargeCfg.interval or 0.08
	local radius = chargeCfg.radius or 3.5
	local radiusJitter = chargeCfg.radiusJitter or 0.2
	local height = chargeCfg.height or 2.5
	local heightJitter = chargeCfg.heightJitter or 0.2
	local arcMinDeg = chargeCfg.arcMinDeg or -70
	local arcMaxDeg = chargeCfg.arcMaxDeg or 70
	local arcSymmetric = chargeCfg.arcSymmetric == true
	local arcOscAmplitude = chargeCfg.arcOscAmplitude or 0.25
	local arcOscSpeed = chargeCfg.arcOscSpeed or 1.4
	local wobble = chargeCfg.wobble or 0.4
	local wobbleSpeed = chargeCfg.wobbleSpeed or 2.0
	local forwardOffset = chargeCfg.forwardOffset or 0
	local templateKey = (self.config.projectile and self.config.projectile.templateKey) or "ManaBall"

	if self._chargeConn then
		self._chargeConn:Disconnect()
	end
	self._chargeConn = RunService.RenderStepped:Connect(function(_dt)
		local rootCf = self:_getRootCFrame()
		local basePos = rootCf.Position + rootCf.LookVector * forwardOffset
		local right = rootCf.RightVector
		local up = rootCf.UpVector
		local forward = rootCf.LookVector
		local t = os.clock()
		for _, orb in ipairs(self._chargeVisuals) do
			local angle = orb.baseAngle + math.sin(t * arcOscSpeed + orb.phase) * arcOscAmplitude
			local x = math.sin(angle) * orb.radius * orb.sideSign
			local y = math.cos(angle) * orb.radius + orb.height
			local planar = right * x + up * y
			local zOffset = wobble * math.sin(t * wobbleSpeed + orb.phase)
			local pos = basePos + planar + forward * zOffset
			orb.offset = rootCf:PointToObjectSpace(pos)
			ProjectilesClient.updateStaticVisual(orb.id, CFrame.new(pos))
		end
	end)

	self._chargeTask = task.spawn(function()
		local rng = Random.new(self._chargeSeed)
		local idx = 1
		while self._chargeActive and idx <= maxCount do
			local rootCf = self:_getRootCFrame()
			local basePos = rootCf.Position + rootCf.LookVector * forwardOffset
			local right = rootCf.RightVector
			local up = rootCf.UpVector
			local forward = rootCf.LookVector
			local minRad = math.rad(math.clamp(arcMinDeg, 0, 90))
			local maxRad = math.rad(math.clamp(arcMaxDeg, 0, 90))
			local angle = rng:NextNumber(minRad, maxRad)
			local sideSign = 1
			if arcSymmetric then
				sideSign = if rng:NextNumber() < 0.5 then -1 else 1
			end
			local radiusScale = rng:NextNumber(1 - radiusJitter, 1 + radiusJitter)
			local heightScale = rng:NextNumber(1 - heightJitter, 1 + heightJitter)
			local phase = rng:NextNumber(0, math.pi * 2)
			local x = math.sin(angle) * radius * radiusScale * sideSign
			local y = math.cos(angle) * radius * radiusScale + height * heightScale
			local planar = right * x + up * y
			local zOffset = wobble * rng:NextNumber(-0.6, 0.6)
			local pos = basePos + planar + forward * zOffset
			local id = ProjectilesClient.spawnStaticVisual(templateKey, CFrame.new(pos))
			if id then
				table.insert(self._chargeVisuals, {
					id = id,
					baseAngle = angle,
					radius = radius * radiusScale,
					height = height * heightScale,
					phase = phase,
					sideSign = sideSign,
					offset = rootCf:PointToObjectSpace(pos),
				})
			end
			idx += 1
			task.wait(interval)
		end
	end)
end

function CascadingManaBallsSkill:_stopCharge()
	self._chargeActive = false
	if self._chargeConn then
		self._chargeConn:Disconnect()
		self._chargeConn = nil
	end
	for _, orb in ipairs(self._chargeVisuals) do
		ProjectilesClient.destroyStaticVisual(orb.id)
	end
	self._chargeVisuals = {}
	self._chargeTask = nil
end

function CascadingManaBallsSkill:_clearPredictedTokens()
	for _, token in ipairs(self._predictedTokens) do
		ProjectilesClient.cancelPredicted(token)
	end
	self._predictedTokens = {}
end

function CascadingManaBallsSkill:cancelLocalPrediction(reason: string?): boolean
	local cancelled = HeldSkill.cancelLocalPrediction(self, reason)
	self:_clearPredictedTokens()
	self._pendingRelease = nil
	self:_stopCharge()
	return cancelled
end

function CascadingManaBallsSkill:onSessionEnded(state: string, reason: string?)
	BaseSkill.onSessionEnded(self, state, reason)
	if state == "COMPLETED" or state == "CANCELLED" then
		self:_clearPredictedTokens()
		self._pendingRelease = nil
		self:_stopCharge()
	end
end

function CascadingManaBallsSkill:_resolveSpawnCFrame(attachPart: string?): CFrame
	local character = Players.LocalPlayer and Players.LocalPlayer.Character
	if character and attachPart then
		local attachTarget = character:FindFirstChild(attachPart, true)
		if attachTarget then
			if attachTarget:IsA("Attachment") then
				return attachTarget.WorldCFrame
			elseif attachTarget:IsA("BasePart") then
				return attachTarget.CFrame
			end
		end
	end
	local root = character and character.PrimaryPart
	if root then
		return root.CFrame
	end
	return CFrame.new()
end

function CascadingManaBallsSkill:onStart(_holdToken: string)
	self:_startCharge()
	return nil
end

function CascadingManaBallsSkill:onRelease(_holdToken: string, attemptId: string?)
	self._chargeActive = false
	self:playCastSoundLocal()

	local animSpec = self.config.anim and self.config.anim.start
	if not animSpec then
		warn("CascadingManaBallsSkill: No start animation configured for", self.name)
		return nil
	end
	local animKey = type(animSpec) == "table" and animSpec.key or animSpec
	if not animKey then
		warn("CascadingManaBallsSkill: Invalid animation spec for", self.name)
		return nil
	end

	local targeting = self.config.targeting or {}
	local targetPos = resolveTargetPos(targeting.maxRange)
	if not targetPos then
		self:showRejectionFeedback("unknown")
		return
	end

	local patternSeed = math.floor((os.clock() * 1e6) % 2147483647)
	local flurry = self.config.flurry or {}
	local projectileSpec = self.config.projectile or {}
	local pattern = projectileSpec.pattern or {}
	local arc = projectileSpec.arc or {}
	local attachPart = projectileSpec.attachPart or projectileSpec.partName or "FX_Hand_R"
	local launchSpeed = projectileSpec.launchSpeed or 80
	local movementType = projectileSpec.movementType or "cascading"

	self._predictedTokens = {}
	self._pendingRelease = {
		targetPos = targetPos,
		patternSeed = patternSeed,
		flurry = flurry,
		projectileSpec = projectileSpec,
		pattern = pattern,
		arc = arc,
		attachPart = attachPart,
		launchSpeed = launchSpeed,
		movementType = movementType,
		attemptId = attemptId,
	}

	local releaseMarker = (self.config.fx and self.config.fx.release) or "release"

	local predictedDuration = self:predictDuration()
	self:playAnimation(animKey, {
		duration = predictedDuration,
		token = attemptId,
	})

	-- Notify server immediately on release; projectiles still wait for marker.
	self:commitRelease({
		targetPos = targetPos,
		patternSeed = patternSeed,
	})

	local track = self.currentAnimationHandle and self.currentAnimationHandle:getTrack()
	if track then
		local conn
		conn = track:GetMarkerReachedSignal(releaseMarker):Connect(function()
			local localEntityId = Registrar.getEntityId(self.player.Character)
			if localEntityId and attemptId and self.currentAttemptId ~= attemptId then
				return
			end
			self:_fireRelease()
			if conn then
				conn:Disconnect()
				conn = nil
			end
		end)
		self.markerEventListenerDestroyers[releaseMarker] = function()
			if conn then
				conn:Disconnect()
				conn = nil
			end
		end
	end

	-- Fallback: if marker never fires, release near the end of the animation.
	if predictedDuration and predictedDuration > 0 then
		task.delay(predictedDuration, function()
			if self._pendingRelease then
				self:_fireRelease()
			end
		end)
	end

	return { deferCommit = true }
end

function CascadingManaBallsSkill:_fireRelease()
	local payload = self._pendingRelease
	if not payload then
		return
	end
	self._pendingRelease = nil

	-- Build charge offsets from current visuals
	local offsets: { Vector3 } = {}
	for _, orb in ipairs(self._chargeVisuals) do
		if typeof(orb.offset) == "Vector3" then
			table.insert(offsets, orb.offset)
		end
	end
	self:_stopCharge()

	-- Notify server that release marker fired.
	local markerPayload = {
		skillName = self.name,
		userId = self.player.UserId,
		inputTime = Clock.serverNow(),
		holdToken = self._holdToken,
		attemptId = self.currentAttemptId,
		chargeOffsets = offsets,
	}
	if Schema.checkSkillRequest(markerPayload) then
		dispatcher:request("SkillRequestMarker", markerPayload)
	end

	local targetPos = payload.targetPos
	local patternSeed = payload.patternSeed
	local flurry = payload.flurry
	local projectileSpec = payload.projectileSpec
	local pattern = payload.pattern
	local arc = payload.arc
	local chargeCfg = self.config.charge or {}
	local attachPart = payload.attachPart
	local launchSpeed = payload.launchSpeed
	local movementType = payload.movementType

	local count = flurry.count or 1
	if #offsets > 0 then
		count = math.min(count, #offsets)
	end
	local interval = flurry.interval or 0
	local jitter = flurry.jitter or 0
	local startDelay = flurry.startDelay or 0

	local rootCf = self:_getRootCFrame()

	for i = 1, count do
		local scheduleRng = Random.new(patternSeed + i * 1337)
		local timeJitter = if jitter > 0 then scheduleRng:NextNumber(-jitter, jitter) else 0
		local delay = math.max(0, startDelay + (i - 1) * interval + timeJitter)
		local token = `{self.currentAttemptId}:{i}`
		table.insert(self._predictedTokens, token)
		task.delay(delay, function()
			if self.currentAttemptId == nil then
				return
			end
			local spawnCf = nil
			local offset = offsets[i]
			if offset and typeof(offset) == "Vector3" then
				spawnCf = rootCf * CFrame.new(offset)
			end
			if not spawnCf then
				spawnCf = self:_resolveSpawnCFrame(attachPart)
			end
			local _forward, right, up = PatternUtils.makeBasis(targetPos - spawnCf.Position)
			local rng = Random.new(patternSeed + i * 9973)
			local circle = PatternUtils.randomInUnitCircle(rng)
			local spread = pattern.spread or 0
			local groupSize = pattern.groupSize or 5
			local verticalBias = pattern.verticalBias or 0.25
			local verticalBiasJitter = pattern.verticalBiasJitter or 0.1
			local phaseJitter = pattern.phaseJitter or (math.pi * 0.2)
			local targetOffset = right * (circle.X * spread) + up * (circle.Y * spread)
			local finalTarget = targetPos + targetOffset

			local dir = finalTarget - spawnCf.Position
			if dir.Magnitude <= 1e-4 then
				dir = spawnCf.LookVector
			end
			local distance = dir.Magnitude
			local flightTimeMin = pattern.flightTimeMin or 0.3
			local flightTimeMax = pattern.flightTimeMax or 1.0
			local flightTime = math.clamp(distance / launchSpeed, flightTimeMin, flightTimeMax)

			local amplitudeBase = pattern.amplitude or 3
			local amplitudeJitter = pattern.amplitudeJitter or 0.2
			local frequencyBase = pattern.frequency or 1
			local frequencyJitter = pattern.frequencyJitter or 0.2
			local amplitude = amplitudeBase * rng:NextNumber(1 - amplitudeJitter, 1 + amplitudeJitter)
			local frequency = frequencyBase * rng:NextNumber(1 - frequencyJitter, 1 + frequencyJitter)
			local sideSign, phase = PatternUtils.computeGroupPhase(i, groupSize, phaseJitter, rng)
			local lateral = PatternUtils.computeLateral(right, up, sideSign, verticalBias, verticalBiasJitter, rng)
			local arcAmplitude = (arc.amplitude or 0)
				* rng:NextNumber(1 - (arc.amplitudeJitter or 0), 1 + (arc.amplitudeJitter or 0))
			local orientationDeg = PatternUtils.pickArcOrientation(
				rng,
				arc.orientationMin or 0,
				arc.orientationMax or 360,
				arc.orientationSymmetric == true
			)
			local arcSideSign = if rng:NextNumber() < 0.5 then -1 else 1
			local arcPlane = arc.plane
			local arcMode = arc.orientationMode
			local arcJitter = arc.orientationJitter or 0
			if arcMode == "outward" then
				local casterPos = rootCf.Position
				local spawnOffset = spawnCf.Position - casterPos
				local forwardDir = finalTarget - spawnCf.Position
				local forward, right, up = PatternUtils.makeBasis(forwardDir)
				local basisB = if arcPlane == "horizontal" then forward else up
				local r = right:Dot(spawnOffset)
				local b = basisB:Dot(spawnOffset)
				if math.abs(r) + math.abs(b) > 1e-4 then
					orientationDeg = math.abs(math.deg(math.atan2(b, r)))
					arcSideSign = if r < 0 then -1 else 1
				end
				local minDeg = arc.orientationMin or 0
				local maxDeg = arc.orientationMax or 90
				local radius = chargeCfg.radius or 3.5
				local height = chargeCfg.height or 2.5
				local heightMin = height - radius
				local heightMax = height + radius
				local heightNow = rootCf.UpVector:Dot(spawnOffset)
				local denom = heightMax - heightMin
				if denom > 1e-4 then
					local t = math.clamp((heightNow - heightMin) / denom, 0, 1)
					local magnitude = minDeg + (maxDeg - minDeg) * t
					orientationDeg = magnitude
				end
			end
			if arcJitter and arcJitter ~= 0 then
				orientationDeg += rng:NextNumber(-arcJitter, arcJitter)
			end

			local movementParams = {
				targetPos = finalTarget,
				flightTime = flightTime,
				amplitude = amplitude,
				frequency = frequency,
				phase = phase,
				lateral = lateral,
				orientationDeg = orientationDeg,
				plane = arcPlane,
				sideSign = arcSideSign,
			}
			if movementType == "arc" then
				movementParams.amplitude = arcAmplitude
				movementParams.frequency = nil
				movementParams.phase = nil
				movementParams.lateral = nil
			end

			local specCopy = {}
			for k, v in pairs(projectileSpec) do
				specCopy[k] = v
			end
			specCopy.movementParams = movementParams
			if projectileSpec.impact and projectileSpec.impact.onEnd == true then
				specCopy.lifetime = flightTime
			end
			if projectileSpec.impact and projectileSpec.impact.mode == "explode" then
				specCopy.extraData = specCopy.extraData or {}
				specCopy.extraData.impactKey = specCopy.extraData.impactKey or "ManaBallImpact"
			end

			local startVel = dir.Unit * launchSpeed
			ProjectilesClient.spawnPredictedReleased(self.name, specCopy, token, spawnCf, startVel)
		end)
	end

	self:commitRelease({
		targetPos = targetPos,
		patternSeed = patternSeed,
	})
end

return CascadingManaBallsSkill
