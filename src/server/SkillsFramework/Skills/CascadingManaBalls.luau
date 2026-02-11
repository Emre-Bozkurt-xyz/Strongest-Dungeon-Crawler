-- CascadingManaBalls: Flurry of mana projectiles with cascading motion
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Server = ServerScriptService.Server

local HeldSkill = require(script.Parent.HeldSkill)
local ProjectileService = require(Server.Services.ProjectileService)
local CombatService = require(Server.Services.CombatService)
local Registrar = require(Server.Services.Registrar)
local EntityUtils = require(ReplicatedStorage.Shared.EntityUtils)
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)
local PatternUtils = require(ReplicatedStorage.Shared.Projectiles.PatternUtils)
local AttachUtils = require(ReplicatedStorage.Shared.Projectiles.AttachUtils)
local HitboxService = require(script.Parent.Parent.HitboxService)
local DebugConfig = require(ReplicatedStorage.Shared.Debug.DebugConfig)
local SharedSpec = require(ReplicatedStorage.Shared.skills.Specs.CascadingManaBalls)

local CascadingManaBalls = {}
CascadingManaBalls.__index = CascadingManaBalls
setmetatable(CascadingManaBalls, { __index = HeldSkill })

local function mergeTables(base: any, override: any): any
	if type(base) ~= "table" and type(override) ~= "table" then
		return override ~= nil and override or base
	end
	local result = {}
	if type(base) == "table" then
		for k, v in pairs(base) do
			result[k] = v
		end
	end
	if type(override) == "table" then
		for k, v in pairs(override) do
			if type(v) == "table" and type(result[k]) == "table" then
				result[k] = mergeTables(result[k], v)
			else
				result[k] = v
			end
		end
	end
	return result
end


function CascadingManaBalls.new(casterId, data)
	local self = HeldSkill.new(casterId, data)
	setmetatable(self, CascadingManaBalls)
	self._pendingRelease = nil
	return self
end

function CascadingManaBalls:onStart(_requestData: any?)
	return { success = true }
end

function CascadingManaBalls:_spawnProjectiles(req: any)
	local chargeCfg = mergeTables(SharedSpec.charge, self.config.charge)
	local casterModel = self:getCasterModel()
	local attachPartName = AttachUtils.resolveAttachPartName(casterModel)
	local projectileCfg = mergeTables(SharedSpec.projectile, self.config.projectileServer)
	local flurryCfg = mergeTables(SharedSpec.flurry, self.config.flurry)
	local patternCfg = projectileCfg.pattern or {}
	local targetCfg = mergeTables(SharedSpec.targeting, self.config.targeting)
	local arcCfg = projectileCfg.arc or {}
	local chargeOffsets = req.chargeOffsets
	local maxChargeRadius = chargeCfg.maxRadius or chargeCfg.radius or nil

	local baseTargetPos = req.targetPos
	if typeof(baseTargetPos) ~= "Vector3" then
		local root = self:getCasterRootPart()
		if root then
			baseTargetPos = root.Position + root.CFrame.LookVector * (targetCfg.maxRange or 90)
		else
			baseTargetPos = Vector3.new(0, 5, -50)
		end
	end
	local root = self:getCasterRootPart()
	if root then
		local maxRange = targetCfg.maxRange or 120
		local toTarget = baseTargetPos - root.Position
		if toTarget.Magnitude > maxRange then
			baseTargetPos = root.Position + toTarget.Unit * maxRange
		end
	end

	local patternSeed = if type(req.patternSeed) == "number"
		then req.patternSeed
		else math.floor((os.clock() * 1e6) % 2147483647)
	local inputTime = if type(req.inputTime) == "number" then req.inputTime else os.clock()
	local inputDelay = math.max(0, os.clock() - inputTime)

	local count = flurryCfg.count or 1
	if type(chargeOffsets) == "table" then
		count = math.min(count, #chargeOffsets)
	end
	local interval = flurryCfg.interval or 0
	local jitter = flurryCfg.jitter or 0
	local startDelay = flurryCfg.startDelay or 0

	local launchSpeed = projectileCfg.launchSpeed or 80
	local lifetime = projectileCfg.lifetime or 3.5
	local radius = projectileCfg.radius or 1.5
	local pierce = projectileCfg.pierce or 1
	local templateKey = projectileCfg.templateKey or "ManaBall"

	local amplitudeBase = patternCfg.amplitude or 3
	local amplitudeJitter = patternCfg.amplitudeJitter or 0.2
	local frequencyBase = patternCfg.frequency or 1
	local frequencyJitter = patternCfg.frequencyJitter or 0.2
	local spread = patternCfg.spread or 0
	local groupSize = patternCfg.groupSize or 5
	local verticalBias = patternCfg.verticalBias or 0.25
	local verticalBiasJitter = patternCfg.verticalBiasJitter or 0.1
	local phaseJitter = patternCfg.phaseJitter or (math.pi * 0.2)
	local flightTimeMin = patternCfg.flightTimeMin or 0.3
	local flightTimeMax = patternCfg.flightTimeMax or 1.0
	local arcAmplitude = arcCfg.amplitude or 0
	local arcAmplitudeJitter = arcCfg.amplitudeJitter or 0
	local arcOrientationMin = arcCfg.orientationMin or 0
	local arcOrientationMax = arcCfg.orientationMax or 360
	local arcOrientationSymmetric = arcCfg.orientationSymmetric == true

	local magicDmg = self:resolveStat(StatTypes.StaticStats.MagicDamage)
	local damageMult = self.config.damageMult or 1
	local baseDamage = magicDmg * damageMult
	local rootPart = self:getCasterRootPart()
	local rootCf = rootPart and rootPart.CFrame or nil

	local function spawnProjectile(index: number)
		local tokenBase = req.attemptId or tostring(patternSeed)
		local token = `{tokenBase}:{index}`

		local spawnCf = nil
		if type(chargeOffsets) == "table" then
			local offset = chargeOffsets[index]
			if typeof(offset) == "Vector3" and rootCf then
				if maxChargeRadius and offset.Magnitude > maxChargeRadius then
					offset = offset.Unit * maxChargeRadius
				end
				spawnCf = rootCf * CFrame.new(offset)
			end
		end
		if not spawnCf then
			spawnCf = AttachUtils.getAttachCFrame(casterModel, attachPartName)
		end
		if not spawnCf and casterModel then
			spawnCf = casterModel:GetPivot()
		end
		spawnCf = spawnCf or CFrame.new()

		local rng = Random.new(patternSeed + index * 9973)
		local randomCircle = PatternUtils.randomInUnitCircle(rng)

		local _forward, right, up = PatternUtils.makeBasis(baseTargetPos - spawnCf.Position)
		local targetPos = baseTargetPos + right * (randomCircle.X * spread) + up * (randomCircle.Y * spread)

		local dir = targetPos - spawnCf.Position
		if dir.Magnitude <= 1e-4 then
			dir = spawnCf.LookVector
		end
		local distance = dir.Magnitude
		local flightTime = math.clamp(distance / launchSpeed, flightTimeMin, flightTimeMax)

		if DebugConfig.isEnabled("projectiles") and index <= 3 then
			print(
				"[CascadingManaBalls]",
				"spawn",
				index,
				"spawnPos=",
				spawnCf.Position,
				"targetPos=",
				targetPos,
				"distance=",
				distance,
				"flightTime=",
				flightTime
			)
		end

		local amplitude = amplitudeBase * rng:NextNumber(1 - amplitudeJitter, 1 + amplitudeJitter)
		local frequency = frequencyBase * rng:NextNumber(1 - frequencyJitter, 1 + frequencyJitter)
		local sideSign, phase = PatternUtils.computeGroupPhase(index, groupSize, phaseJitter, rng)
		local lateral = PatternUtils.computeLateral(right, up, sideSign, verticalBias, verticalBiasJitter, rng)
		local arcAmplitudeFinal = arcAmplitude * rng:NextNumber(1 - arcAmplitudeJitter, 1 + arcAmplitudeJitter)
		local orientationDeg = PatternUtils.pickArcOrientation(
			rng,
			arcOrientationMin,
			arcOrientationMax,
			arcOrientationSymmetric
		)
		local arcSideSign = if rng:NextNumber() < 0.5 then -1 else 1
		local arcPlane = arcCfg.plane
		local arcMode = arcCfg.orientationMode
		local arcJitter = arcCfg.orientationJitter or 0
		if arcMode == "outward" and rootCf then
			local casterPos = rootCf.Position
			local spawnOffset = spawnCf.Position - casterPos
			local forwardDir = targetPos - spawnCf.Position
			if forwardDir.Magnitude <= 1e-4 then
				forwardDir = spawnCf.LookVector
			end
			local forward, right, up = PatternUtils.makeBasis(forwardDir)
			local basisB = if arcPlane == "horizontal" then forward else up
			local r = right:Dot(spawnOffset)
			local b = basisB:Dot(spawnOffset)
			if math.abs(r) + math.abs(b) > 1e-4 then
				orientationDeg = math.abs(math.deg(math.atan2(b, r)))
				arcSideSign = if r < 0 then -1 else 1
			end
			local minDeg = arcOrientationMin
			local maxDeg = arcOrientationMax
			local radiusForHeight = chargeCfg.radius or 3.5
			local heightForCenter = chargeCfg.height or 2.5
			local heightMin = heightForCenter - radiusForHeight
			local heightMax = heightForCenter + radiusForHeight
			local heightNow = rootCf.UpVector:Dot(spawnOffset)
			local denom = heightMax - heightMin
			if denom > 1e-4 then
				local t = math.clamp((heightNow - heightMin) / denom, 0, 1)
				local magnitude = minDeg + (maxDeg - minDeg) * t
				orientationDeg = magnitude
			end
		end
		if arcJitter ~= 0 then
			orientationDeg += rng:NextNumber(-arcJitter, arcJitter)
		end

		local impactCfg = projectileCfg.impact or {}
		local movementType = projectileCfg.movementType or "cascading"
		local movementParams = {
			targetPos = targetPos,
			flightTime = flightTime,
			amplitude = amplitude,
			frequency = frequency,
			phase = phase,
			lateral = lateral,
			orientationDeg = orientationDeg,
			plane = arcPlane,
			sideSign = arcSideSign,
			endOnArrival = impactCfg.onEnd == true,
		}
		if movementType == "arc" then
			movementParams.amplitude = arcAmplitudeFinal
			movementParams.frequency = nil
			movementParams.phase = nil
			movementParams.lateral = nil
		end
		ProjectileService.spawnProjectile({
			templateKey = templateKey,
			cframe = spawnCf,
			velocity = dir.Unit * launchSpeed,
			skillName = self.name,
			launchSpeed = launchSpeed,
			movementType = movementType,
			movementParams = movementParams,
			lifetime = lifetime,
			radius = radius,
			pierce = pierce,
			owner = self.caster,
			faction = EntityUtils.getFaction(self.caster),
			extraData = { impactKey = "ManaBallImpact" },
			token = token,
			onHit = function(_proj, _hitPart, hitEntity, hitResult)
				local attack = self:resolveAttack({
					damage = baseDamage,
					damageType = "Magic",
				})

				if impactCfg.mode == "explode" then
					local radiusImpact = impactCfg.radius or 6
					local impactPos = hitResult and hitResult.Position or (_proj and _proj.position) or spawnCf.Position
					local originCf = CFrame.new(impactPos)
					local targets = HitboxService.querySphere(originCf, radiusImpact, {
						casterEntityId = self.casterId,
						factionRelation = "enemy",
						includeCaster = false,
					})
					for _, model in ipairs(targets) do
						local targetEntityId = Registrar.getEntityId(model)
						if targetEntityId then
							CombatService.applyAttack(targetEntityId, attack, self.casterId)
						end
					end
				else
					local targetEntityId = Registrar.getEntityId(hitEntity)
					if targetEntityId then
						CombatService.applyAttack(targetEntityId, attack, self.casterId)
					end
				end
				return false
			end,
			onEnd = function(_proj, endPos)
				if impactCfg.mode ~= "explode" or impactCfg.onEnd ~= true then
					return
				end
				local radiusImpact = impactCfg.radius or 6
				local originCf = CFrame.new(endPos)
				local targets = HitboxService.querySphere(originCf, radiusImpact, {
					casterEntityId = self.casterId,
					factionRelation = "enemy",
					includeCaster = false,
				})
				local attack = self:resolveAttack({
					damage = baseDamage,
					damageType = "Magic",
				})
				for _, model in ipairs(targets) do
					local targetEntityId = Registrar.getEntityId(model)
					if targetEntityId then
						CombatService.applyAttack(targetEntityId, attack, self.casterId)
					end
				end
			end,
		})
	end

	for i = 1, count do
		local rng = Random.new(patternSeed + i * 1337)
		local timeJitter = if jitter > 0 then rng:NextNumber(-jitter, jitter) else 0
		local scheduled = startDelay + (i - 1) * interval + timeJitter
		local adjusted = math.max(0, scheduled - inputDelay)
		self:guardedDelay(adjusted, function()
			spawnProjectile(i)
		end)
	end

end

function CascadingManaBalls:onRelease(requestData: any?)
	local req = requestData or {}
	local timing = self:resolveTiming()
	req.timing = timing

	if not self:applyResourceCost(req) then
		return
	end

	local durationScale = timing.durationScale
	local executionDuration = (self.config.baseDuration or 0.5) * durationScale

	self:_updateExecutionState({
		timing = timing,
		durationScale = durationScale,
		plannedDuration = executionDuration,
		targetDuration = executionDuration,
	})
	self._pendingRelease = {
		holdToken = req.holdToken,
		attemptId = req.attemptId,
		targetPos = req.targetPos,
		patternSeed = req.patternSeed,
		inputTime = req.inputTime,
		timing = timing,
	}

	self:guardedDelay(executionDuration, function()
		self._pendingRelease = nil
		self:completeExecution()
	end)

	return {
		success = true,
		data = {
			duration = executionDuration,
		},
	}
end

function CascadingManaBalls:onReleaseMarker(requestData: any?): (any?, string?)
	if not self._pendingRelease then
		return nil, "no_pending_release"
	end
	local req = requestData or {}
	if self._pendingRelease.holdToken and req.holdToken and req.holdToken ~= self._pendingRelease.holdToken then
		return nil, "hold_token_mismatch"
	end
	if self._pendingRelease.attemptId and req.attemptId and req.attemptId ~= self._pendingRelease.attemptId then
		return nil, "attempt_mismatch"
	end
	local pending = self._pendingRelease
	if type(req.chargeOffsets) == "table" then
		pending.chargeOffsets = req.chargeOffsets
	end
	self._pendingRelease = nil
	self:_spawnProjectiles(pending)
	return { success = true }
end

return CascadingManaBalls
