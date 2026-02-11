--!strict
-- PredictionController: centralized client prediction + reconciliation helpers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AttemptStore = require(script.Parent.AttemptStore)
local SessionMirror = require(script.Parent.SessionMirror)
local Clock = require(ReplicatedStorage.Shared.Time.Clock)

local PredictionController = {}

function PredictionController.beginLocal(
	skillName: string,
	casterId: any?,
	comboInfo: { currentStep: number, totalSteps: number, windowOpensAt: number?, windowExpiresAt: number? }?,
	predictedDuration: number?,
	metadata: { [string]: any }?
): string?
	local attempt = AttemptStore.beginLocal(skillName, casterId, comboInfo and comboInfo.currentStep or nil, comboInfo and comboInfo.totalSteps or nil, metadata)
	local now = Clock.localNow()
	local expiresAt = predictedDuration and (now + predictedDuration) or nil
	SessionMirror.predictStart(skillName, comboInfo, expiresAt)
	return attempt.id
end

function PredictionController.markPending(attemptId: string?)
	if attemptId then
		AttemptStore.markPending(attemptId)
	end
end

function PredictionController.confirm(attemptId: string?, data: any?)
	if attemptId then
		AttemptStore.confirm(attemptId, data)
	end
end

function PredictionController.complete(attemptId: string?, reason: string?)
	if attemptId then
		AttemptStore.complete(attemptId, reason)
	end
end

function PredictionController.reject(attemptId: string?, reason: string?, skillName: string?)
	if attemptId then
		AttemptStore.reject(attemptId, reason)
	end
	if skillName then
		SessionMirror.cancelPrediction(skillName)
	end
end

return PredictionController
