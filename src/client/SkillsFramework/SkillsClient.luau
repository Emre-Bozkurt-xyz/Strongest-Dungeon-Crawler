local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Networking = require(ReplicatedStorage.Shared.Networking)
local SessionMirror = require(script.Parent.SessionMirror)
local Replicator = require(script.Parent.Parent.fx.Replicator)
local AnimationCoordinator = require(script.Parent.Parent.Animation.AnimationCoordinator)
local DebugConfig = require(ReplicatedStorage.Shared.Debug.DebugConfig)
local SkillPacer = require(script.Parent.SkillPacer)
local SkillMetadataClient = require(script.Parent.SkillMetadataClient)
local Registrar = require(script.Parent.Parent.Services.Registrar)

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

local function debugCancelEnabled(): boolean
	return DEBUG_CANCELLATION or DebugConfig.isEnabled("cancelDebug")
end

local availableSkills = {} :: { [string]: any }

local function startCancelCooldown(skillName: string, skill: any?, reason: string?)
	if reason == "insufficient_resources" then
		return
	end
	local metadata = SkillMetadataClient.get(skillName)
	local cooldownOnCancel = if metadata ~= nil then metadata.cooldownOnCancel else (skill and skill.config and skill.config.cooldownOnCancel)
	if cooldownOnCancel == false then
		return
	end
	local cooldown = (metadata and metadata.cooldown) or (skill and skill.config and skill.config.cooldown) or nil
	local gcd = (metadata and metadata.gcd) or (skill and skill.config and skill.config.gcd) or nil
	local comboCooldown = (metadata and metadata.combo and metadata.combo.comboCooldown)
		or (skill and skill.config and skill.config.combo and skill.config.combo.comboCooldown)
	if comboCooldown ~= nil then
		cooldown = comboCooldown
	end
	SkillPacer.cancelSkill(skillName, cooldown, gcd)
end

local function getLocalEntityId(): string?
	return Registrar.getLocalEntityId()
end

local function cancelAllLocalPredictedSkills(reason: string)
	debugCancel("========== CANCEL ALL CALLED ==========")
	debugCancel("Reason:", reason)
	local cancelCount = 0
	for skillName, skill in pairs(availableSkills) do
		local isActive = SkillPacer.isActive(skillName)
		if not isActive then
			if debugCancelEnabled() then
				debugCancel("Skipping inactive skill:", skillName, SkillPacer.getStateSnapshot(skillName))
			end
			continue
		end
		if type(skill) == "table" and type(skill.cancelLocalPrediction) == "function" then
			debugCancel("Attempting to cancel:", skillName)
			if debugCancelEnabled() then
				debugCancel("Skill state:", {
					attemptId = skill.currentAttemptId,
					sessionId = skill.currentSessionId,
					hasAnim = skill.currentAnimationHandle ~= nil,
					hasSound = skill.currentCastSoundPart ~= nil,
				})
			end
			local cancelled = skill:cancelLocalPrediction(reason)
			if cancelled then
				startCancelCooldown(skillName, skill, reason)
			end
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
		if payload.state == "CANCELLED" then
			startCancelCooldown(payload.skillId, skill, payload.reason)
		end
	elseif skill and payload.state == "CANCELLED" and skill.cancelLocalPrediction then
		local cancelled = skill:cancelLocalPrediction(payload.reason)
		if cancelled then
			startCancelCooldown(payload.skillId, skill, payload.reason)
		end
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
	if debugCancelEnabled() then
		debugCancel("StatusEffectBlocking:", payload)
	end
	if blocked == true and (action == "cast" or action == "all") then
		cancelAllLocalPredictedSkills("blocked")
	end
end)

-- update client state for active skills
dispatcher:on("SkillsUpdate", function(payload: any, _meta: any?)
	if type(payload) ~= "table" then
		warn("SkillsUpdate: invalid payload type", typeof(payload))
		return
	end
	if payload.updateType == "skill_added" then
		if type(payload.data) ~= "table" then
			warn("SkillsUpdate: missing data for skill_added")
			return
		end
		local skillName = payload.data.skillName
		if type(skillName) ~= "string" or skillName == "" then
			warn("SkillsUpdate: invalid skillName", skillName)
			return
		end

		-- instantiate skill class and store in availableSkills
		local skillSpec = ClientSpec[skillName]
		if not skillSpec then
			warn("SkillsUpdate: no client spec for skill", skillName)
			return
		end
		if type(skillSpec.class) ~= "string" then
			warn("SkillsUpdate: invalid class for skill", skillName, "class=", tostring(skillSpec.class))
			return
		end
		local skillClassModule = script.Parent.Skills:FindFirstChild(skillSpec.class)
		if not skillClassModule then
			warn("SkillsUpdate: missing skill class module", skillSpec.class)
			return
		end
		local okClass, skillClass = pcall(require, skillClassModule)
		if not okClass then
			warn("SkillsUpdate: failed to require class", skillSpec.class, skillClass)
			return
		end
		if type(skillClass) ~= "table" or type(skillClass.new) ~= "function" then
			warn("SkillsUpdate: invalid class export for", skillSpec.class)
			return
		end
		local okInstance, skillInstance = pcall(skillClass.new, skillName, skillSpec)
		if not okInstance then
			warn("SkillsUpdate: failed to create instance for", skillName, skillInstance)
			return
		end
		availableSkills[skillName] = skillInstance
	end
end)

function SkillsClient.useSkill(skillName: string)
	local skill = availableSkills[skillName]
	if skill then
		skill:use()
	end
end

function SkillsClient.releaseSkill(skillName: string)
	local skill = availableSkills[skillName]
	if skill and type(skill.release) == "function" then
		skill:release()
	end
end

return SkillsClient
