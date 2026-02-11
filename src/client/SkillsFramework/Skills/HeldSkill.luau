--!strict
-- HeldSkill: Base class for press-and-hold skills with explicit start/release flow.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local BaseSkill = require(script.Parent.BaseSkill)
local SkillPacer = require(script.Parent.Parent.SkillPacer)
local SkillMetadataClient = require(script.Parent.Parent.SkillMetadataClient)
local PredictionController = require(script.Parent.Parent.PredictionController)
local Networking = require(ReplicatedStorage.Shared.Networking)
local Schema = require(ReplicatedStorage.Shared.Debug.Schema)
local Clock = require(ReplicatedStorage.Shared.Time.Clock)

local dispatcher = Networking.client()

local HeldSkill = {}
HeldSkill.__index = HeldSkill
setmetatable(HeldSkill, BaseSkill)

function HeldSkill.new(name: string?, config: any?)
	local self = setmetatable(BaseSkill.new(name, config), HeldSkill)
	self._holding = false
	self._holdToken = nil
	self._holdStartedAt = 0
	self._releaseCommitted = false
	self._autoReleaseTask = nil
	return self
end

function HeldSkill:isHolding(): boolean
	return self._holding == true
end

function HeldSkill:_getMaxHoldDuration(): number?
	local metadata = SkillMetadataClient.get(self.name)
	local custom = metadata and metadata.customData
	local maxHold = custom and custom.holdMaxDuration
	if type(maxHold) == "number" then
		return maxHold
	end
	local cfgHold = self.config and self.config.hold
	if cfgHold and type(cfgHold.maxDuration) == "number" then
		return cfgHold.maxDuration
	end
	return nil
end

function HeldSkill:requestHoldStartAsync(holdToken: string, extra: { [string]: any }?)
	task.spawn(function()
		local payload = {
			skillName = self.name,
			userId = self.player.UserId,
			inputTime = Clock.serverNow(),
			holdToken = holdToken,
		}
		if extra and type(extra) == "table" then
			for k, v in pairs(extra) do
				payload[k] = v
			end
		end
		if not Schema.checkSkillRequest(payload) then
			return
		end
		local response = dispatcher:request("SkillRequestStart", payload)
		if not response or not response.success then
			self._holding = false
			self._holdToken = nil
		end
	end)
end

function HeldSkill:requestHoldReleaseAsync(
	holdToken: string,
	attemptId: string?,
	extra: { [string]: any }?
)
	task.spawn(function()
		if attemptId then
			PredictionController.markPending(attemptId)
		end
		local payload = {
			skillName = self.name,
			userId = self.player.UserId,
			inputTime = Clock.serverNow(),
			holdToken = holdToken,
			attemptId = attemptId,
		}
		if extra and type(extra) == "table" then
			for k, v in pairs(extra) do
				payload[k] = v
			end
		end
		if not Schema.checkSkillRequest(payload) then
			if attemptId then
				PredictionController.reject(attemptId, "invalid_request", self.name)
			end
			return
		end
		local response = dispatcher:request("SkillRequestRelease", payload)
		if response and response.success then
			if response.data and response.data.sessionId then
				self:_attachSessionId(response.data.sessionId)
			end
			if attemptId then
				PredictionController.confirm(attemptId, response.data)
			end
		else
			if attemptId then
				PredictionController.reject(attemptId, response and response.error or "rejected", self.name)
			end
		end
	end)
end

-- Override in subclasses to implement charge visuals.
function HeldSkill:onStart(_holdToken: string): { [string]: any }?
	return nil
end

-- Override in subclasses. Return { deferCommit = true } to delay commitRelease.
function HeldSkill:onRelease(_holdToken: string, _attemptId: string?): { [string]: any }?
	return nil
end

function HeldSkill:commitRelease(extra: { [string]: any }?)
	if self._releaseCommitted then
		return
	end
	self._releaseCommitted = true
	local attemptId = self.currentAttemptId
	self:requestHoldReleaseAsync(self._holdToken, attemptId, extra)
end

function HeldSkill:use()
	if self._holding then
		return
	end
	local canUse, rejectionReason = self:canUseLocally()
	if not canUse then
		self:showRejectionFeedback(rejectionReason :: any)
		return
	end

	self._holding = true
	self._releaseCommitted = false
	self._holdToken = HttpService:GenerateGUID(false)
	self._holdStartedAt = os.clock()
	SkillPacer.beginHold(self.name)

	local startExtra = self:onStart(self._holdToken) or nil
	self:requestHoldStartAsync(self._holdToken, startExtra)

	local maxHold = self:_getMaxHoldDuration()
	if type(maxHold) == "number" and maxHold > 0 then
		task.delay(maxHold, function()
			if self._holding and self._holdToken then
				self:release()
			end
		end)
	end
end

function HeldSkill:release()
	if not self._holding then
		return
	end
	self._holding = false

	local predictedDuration = self:predictDuration()
	local attemptId = self:_predictSession(nil, predictedDuration, { holdToken = self._holdToken })

	local metadata = SkillMetadataClient.get(self.name)
	local cooldown = metadata and metadata.cooldown or nil
	local gcd = metadata and metadata.gcd or nil
	SkillPacer.endHold(self.name)
	SkillPacer.recordSkillUse(self.name, predictedDuration, cooldown, gcd)

	local releaseExtra = self:onRelease(self._holdToken, attemptId)
	if type(releaseExtra) == "table" and releaseExtra.deferCommit == true then
		return
	end
	self:commitRelease(releaseExtra)
end

function HeldSkill:cancelLocalPrediction(reason: string?): boolean
	local cancelled = BaseSkill.cancelLocalPrediction(self, reason)
	self._holding = false
	self._holdToken = nil
	self._releaseCommitted = false
	SkillPacer.endHold(self.name)
	return cancelled
end

return HeldSkill
