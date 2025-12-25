local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Networking = require(ReplicatedStorage.Shared.Networking)
local SessionMirror = require(script.Parent.SessionMirror)
local Replicator = require(script.Parent.Parent.fx.Replicator)
local AnimationCoordinator = require(script.Parent.Parent.Animation.AnimationCoordinator)

-- AnimationCoordinator wraps AnimationPlayer usage for semantic marker events
local _AnimationPlayer = require(script.Parent.Parent.fx.AnimationPlayer)
local ClientSpec = require(ReplicatedStorage.Shared.skills.ClientSpec)

local SkillsClient = {}

local SKILLS_CHANNEL_NAME = "Skills"
local dispatcher = Networking.client()
local dispatcherAny = dispatcher :: any
dispatcherAny:_ensureChannel(SKILLS_CHANNEL_NAME)

-- Also listen for status effects so we can cancel local prediction immediately
dispatcherAny:_ensureChannel("StatusEffects")

-- DEBUG: Track cancellation to diagnose spam issues
local DEBUG_CANCELLATION = false
local function debugCancel(...)
	if DEBUG_CANCELLATION then
		print("[CANCEL-DEBUG]", ...)
	end
end

local availableSkills = {} :: { [string]: any }

local function getLocalEntityId(): string?
	local char = Players.LocalPlayer and Players.LocalPlayer.Character
	local entityId = char and char:GetAttribute("EntityId")
	if type(entityId) == "string" and entityId ~= "" then
		return entityId
	end
	return nil
end

local function cancelAllLocalPredictedSkills(reason: string)
	debugCancel("========== CANCEL ALL CALLED ==========")
	debugCancel("Reason:", reason)
	local cancelCount = 0
	for skillName, skill in pairs(availableSkills) do
		if type(skill) == "table" and type(skill.cancelLocalPrediction) == "function" then
			debugCancel("Attempting to cancel:", skillName)
			skill:cancelLocalPrediction(reason)
			cancelCount += 1
		end
	end
	debugCancel("Total skills cancelled:", cancelCount)
end

SessionMirror.onStateChanged(function(payload)
	if payload.state ~= "COMPLETED" and payload.state ~= "CANCELLED" then
		return
	end

	local casterId = payload.casterId
	if type(casterId) == "string" and casterId ~= "" then
		Replicator.stopAllForSkill(casterId, payload.skillId)
	end

	if payload.state == "CANCELLED" and payload.sessionId then
		AnimationCoordinator.stopSession(payload.sessionId)
	end

	local localEntityId = getLocalEntityId()
	if not localEntityId or payload.casterId ~= localEntityId then
		return
	end

	local skill = availableSkills[payload.skillId]
	if skill and skill.onSessionEnded then
		skill:onSessionEnded(payload.state, payload.reason)
	elseif skill and payload.state == "CANCELLED" and skill.cancelLocalPrediction then
		skill:cancelLocalPrediction(payload.reason)
	end
end)

dispatcher:on("StatusEffectBlocking", function(payload: any, _meta: any?)
	local localEntityId = getLocalEntityId()
	if not localEntityId or type(payload) ~= "table" then
		return
	end
	if payload.entityId ~= localEntityId then
		return
	end

	local action = payload.action
	local blocked = payload.blocked
	if blocked == true and (action == "cast" or action == "all") then
		cancelAllLocalPredictedSkills("blocked")
	end
end)

-- update client state for active skills
dispatcher:on("SkillsUpdate", function(payload: any, _meta: any?)
	if payload.updateType == "skill_added" then
		local skillName = payload.data.skillName

		-- instantiate skill class and store in availableSkills
		local skillSpec = ClientSpec[skillName]
		if skillSpec and type(skillSpec.class) == "string" then
			local skillClassModule = script.Parent.Skills[skillSpec.class]
			if skillClassModule then
				local skillInstance = require(skillClassModule).new(skillName, skillSpec)
				availableSkills[skillName] = skillInstance
			end
		end
	end
end)

function SkillsClient.useSkill(skillName: string)
	local skill = availableSkills[skillName]
	if skill then
		skill:use()
	end
end

return SkillsClient
