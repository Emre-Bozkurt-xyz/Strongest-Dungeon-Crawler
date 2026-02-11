local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaseSkill = require(script.Parent.BaseSkill)
local Networking = require(ReplicatedStorage.Shared.Networking)
local Schema = require(ReplicatedStorage.Shared.Debug.Schema)
local SkillPacer = require(script.Parent.Parent.SkillPacer)
local SkillMetadataClient = require(script.Parent.Parent.SkillMetadataClient)
local MovementController = require(script.Parent.Parent.Parent.Movement.MovementController)
local MovementDirectionProvider = require(script.Parent.Parent.Parent.Movement.MovementDirectionProvider)
local MovementSpec = require(ReplicatedStorage.Shared.Movement.MovementSpec)
local Clock = require(ReplicatedStorage.Shared.Time.Clock)
local CameraController = require(script.Parent.Parent.Parent.CameraController)

local dispatcher = Networking.client()
dispatcher:_ensureChannel("Skills")

local DodgeRollSkill = {}
DodgeRollSkill.__index = DodgeRollSkill
setmetatable(DodgeRollSkill, BaseSkill)

function DodgeRollSkill.new(name: string?, config: any?)
	local self = setmetatable(BaseSkill.new(name, config), DodgeRollSkill)
	self._movementId = nil
	self._orientationCleanup = nil
	self._orientationToken = 0
	self._cameraModId = nil
	return self
end

local function getDirectionLabel(direction: Vector3): string
	return MovementDirectionProvider.quantize(direction, MovementDirectionProvider.getReferenceCFrame())
end

local function cloneTable(source: { [string]: any }?): { [string]: any }
	local target: { [string]: any } = {}
	if not source then
		return target
	end
	for key, value in pairs(source) do
		target[key] = value
	end
	return target
end

function DodgeRollSkill:use()
	local canUse, rejectionReason = self:canUseLocally()
	if not canUse then
		self:showRejectionFeedback(rejectionReason :: any)
		return
	end

	local direction = MovementDirectionProvider.getMoveDirection()
	local directionLabel = getDirectionLabel(direction)
	local directional = self.config and self.config.directional
	local visuals = directional and directional[directionLabel] or nil
	local visualAnim = visuals and visuals.anim or nil
	local visualFx = visuals and visuals.fx or nil
	local visualHitSounds = visuals and visuals.hitSounds or nil
	local visualCastSounds = visuals and visuals.castSounds or nil
	local visualCamera = visuals and visuals.camera or nil

	self:playCastSoundLocal(visualCastSounds or (self.config and self.config.castSounds) or nil)

	local animSpec = self.config.anim and self.config.anim.start
	if visualAnim and visualAnim.start then
		animSpec = visualAnim.start
	end
	if not animSpec then
		warn("DodgeRollSkill: No start animation configured for", self.name)
		return
	end
	local animKey = type(animSpec) == "table" and animSpec.key or animSpec
	if not animKey then
		warn("DodgeRollSkill: Invalid animation spec for", self.name)
		return
	end

	local metadata = SkillMetadataClient.get(self.name)
	if not metadata then
		self:showRejectionFeedback("unknown")
		return
	end
	local predictedDuration = self:predictDuration() or metadata.baseDuration or metadata.executionDuration
	if not predictedDuration then
		self:showRejectionFeedback("unknown")
		return
	end
	local cooldown = metadata.cooldown or nil
	local gcd = metadata.gcd or nil

	SkillPacer.recordSkillUse(self.name, predictedDuration, cooldown, gcd)
	self:_predictSession(nil, predictedDuration)

	self:playAnimation(animKey, {
		duration = predictedDuration,
		fx = visualFx or (self.config and self.config.fx) or nil,
		hitSounds = visualHitSounds or (self.config and self.config.hitSounds) or nil,
	})

	if self._orientationCleanup then
		self._orientationCleanup()
		self._orientationCleanup = nil
	end
	self._orientationToken += 1
	local orientationToken = self._orientationToken
	self._orientationCleanup = MovementController.startFacingDirection(
		direction,
		{ restoreToCamera = true }
	)
	local restoreLead = (self.config and self.config.restoreLead) or 0.1
	local restoreDelay = math.max(predictedDuration - restoreLead, 0)
	task.delay(restoreDelay, function()
		if self._orientationCleanup and self._orientationToken == orientationToken then
			self._orientationCleanup()
			self._orientationCleanup = nil
		end
	end)

	if visualCamera or (self.config and self.config.camera) then
		local camSpec = cloneTable(visualCamera or self.config.camera)
		if camSpec.duration == nil then
			camSpec.duration = predictedDuration
		end
		local cam = CameraController.getInstance()
		self._cameraModId = cam:pushModifier(camSpec)
	end

	local dashDistance = metadata.customData and metadata.customData.distance or nil
	if not dashDistance then
		self:showRejectionFeedback("unknown")
		return
	end

	local movement = MovementSpec.buildRollSpec({
		id = self.currentAttemptId,
		sourceSkill = self.name,
		startTime = Clock.localNow(),
		duration = predictedDuration,
		distance = dashDistance,
		direction = MovementDirectionProvider.getMoveDirection(),
	})
	self._movementId = MovementController.startLocalRoll(movement)

	self:requestUseAsync(function(data)
		if data and data.movement then
			MovementController.reconcileDash(data.movement, self._movementId)
		end
	end, function(reason)
		MovementController.cancelDash(self._movementId, reason)
		if self._orientationCleanup then
			self._orientationCleanup()
			self._orientationCleanup = nil
		end
		if self._cameraModId then
			CameraController.getInstance():popModifier(self._cameraModId)
			self._cameraModId = nil
		end
		self._orientationToken += 1
	end)
end

function DodgeRollSkill:requestUse(attemptId: string?): any
	local payload = {
		skillName = self.name,
		userId = self.player.UserId,
		attemptId = attemptId,
		inputTime = Clock.serverNow(),
		direction = MovementDirectionProvider.getMoveDirection(),
	}
	if not Schema.checkSkillRequest(payload) then
		return { success = false, error = "invalid_request" }
	end
	return dispatcher:request("SkillRequestUse", payload)
end

function DodgeRollSkill:onSessionEnded(state: string, reason: string?)
	BaseSkill.onSessionEnded(self, state, reason)
	if state == "CANCELLED" or state == "COMPLETED" then
		MovementController.cancelDash(self._movementId, reason)
		if self._orientationCleanup then
			self._orientationCleanup()
			self._orientationCleanup = nil
		end
		if self._cameraModId then
			CameraController.getInstance():popModifier(self._cameraModId)
			self._cameraModId = nil
		end
		self._orientationToken += 1
	end
end

return DodgeRollSkill
