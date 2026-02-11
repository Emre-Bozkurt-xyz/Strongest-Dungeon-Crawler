--!strict
-- Schema: minimal dev-only payload validation helpers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DebugConfig = require(ReplicatedStorage.Shared.Debug.DebugConfig)

local Schema = {}

local function warnInvalid(name: string, reason: string)
	if DebugConfig.isEnabled("schema") then
		warn(`[Schema] Invalid {name}: {reason}`)
	end
end

function Schema.checkSkillRequest(payload: any): boolean
	if not DebugConfig.isEnabled("schema") then
		return true
	end
	if type(payload) ~= "table" then
		warnInvalid("SkillRequest", "payload not a table")
		return false
	end
	if type(payload.skillName) ~= "string" or payload.skillName == "" then
		warnInvalid("SkillRequest", "missing skillName")
		return false
	end
	if payload.inputTime ~= nil and type(payload.inputTime) ~= "number" then
		warnInvalid("SkillRequest", "inputTime must be number")
		return false
	end
	if payload.attemptId ~= nil and type(payload.attemptId) ~= "string" then
		warnInvalid("SkillRequest", "attemptId must be string")
		return false
	end
	if payload.holdToken ~= nil and type(payload.holdToken) ~= "string" then
		warnInvalid("SkillRequest", "holdToken must be string")
		return false
	end
	return true
end

function Schema.checkSessionEvent(payload: any): boolean
	if not DebugConfig.isEnabled("schema") then
		return true
	end
	if type(payload) ~= "table" then
		warnInvalid("SessionEvent", "payload not a table")
		return false
	end
	if type(payload.sessionId) ~= "string" then
		warnInvalid("SessionEvent", "sessionId missing")
		return false
	end
	if type(payload.casterId) ~= "string" then
		warnInvalid("SessionEvent", "casterId missing")
		return false
	end
	if type(payload.skillId) ~= "string" then
		warnInvalid("SessionEvent", "skillId missing")
		return false
	end
	if type(payload.state) ~= "string" then
		warnInvalid("SessionEvent", "state missing")
		return false
	end
	if type(payload.serverTime) ~= "number" then
		warnInvalid("SessionEvent", "serverTime missing")
		return false
	end
	return true
end

return Schema
