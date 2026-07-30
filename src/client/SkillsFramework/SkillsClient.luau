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

-- Instantiate a skill class and store it in availableSkills.
-- Shared by the SkillsUpdate delta path and the snapshot catch-up path.
-- Idempotent: re-registering an already-known skill is a no-op.
local function registerSkill(skillName: string, source: string): boolean
	if type(skillName) ~= "string" or skillName == "" then
		warn(`{source}: invalid skillName`, skillName)
		return false
	end
	if availableSkills[skillName] then
		return true
	end

	local skillSpec = ClientSpec[skillName]
	if not skillSpec then
		warn(`{source}: no client spec for skill`, skillName)
		return false
	end
	if type(skillSpec.class) ~= "string" then
		warn(`{source}: invalid class for skill`, skillName, "class=", tostring(skillSpec.class))
		return false
	end
	local skillClassModule = script.Parent.Skills:FindFirstChild(skillSpec.class)
	if not skillClassModule then
		warn(`{source}: missing skill class module`, skillSpec.class)
		return false
	end
	local okClass, skillClass = pcall(require, skillClassModule)
	if not okClass then
		warn(`{source}: failed to require class`, skillSpec.class, skillClass)
		return false
	end
	if type(skillClass) ~= "table" or type(skillClass.new) ~= "function" then
		warn(`{source}: invalid class export for`, skillSpec.class)
		return false
	end
	local okInstance, skillInstance = pcall(skillClass.new, skillName, skillSpec)
	if not okInstance then
		warn(`{source}: failed to create instance for`, skillName, skillInstance)
		return false
	end

	availableSkills[skillName] = skillInstance
	if DebugConfig.isEnabled("inputFlow") then
		print("[InputFlow]", `registered skill '{skillName}' via {source}`)
	end
	return true
end

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
		registerSkill(payload.data.skillName, "SkillsUpdate")
	end
end)

-- Ask the server for the authoritative skill list and register anything we missed.
--
-- Skills are granted server-side as soon as the character registers, which is frequently before
-- this module has loaded and subscribed to SkillsUpdate. Those deltas are lost with no error, so
-- the client pulls the full list once it is ready rather than assuming it was listening in time.
-- Safe to call more than once; registerSkill ignores skills already present.
function SkillsClient.requestSnapshot()
	local ok, payload = pcall(function()
		return dispatcherAny:request("SkillsSnapshot", {})
	end)
	if not ok then
		warn("SkillsClient: skills snapshot request failed:", payload)
		return
	end
	if type(payload) ~= "table" or type(payload.skills) ~= "table" then
		warn("SkillsClient: invalid skills snapshot:", typeof(payload))
		return
	end

	local registered = 0
	for _, skillName in ipairs(payload.skills) do
		if registerSkill(skillName, "SkillsSnapshot") then
			registered += 1
		end
	end
	if DebugConfig.isEnabled("inputFlow") then
		print("[InputFlow]", `SkillsSnapshot: {registered}/{#payload.skills} skill(s) available`)
	end
end

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
