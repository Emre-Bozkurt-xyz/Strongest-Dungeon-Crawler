--!strict
-- ActionPermissions Server - Queries SessionManager + StatusEffectsService for authoritative permission checks

local Server = {}

local StatusEffectsService = require(game.ServerScriptService.Server.StatusEffects.StatusEffectsService)
local StatsManager = require(game.ServerScriptService.Server.Stats.StatsManager)
local DebugConfig = require(game:GetService("ReplicatedStorage").Shared.Debug.DebugConfig)

local function debugLog(...: any)
	if DebugConfig.isEnabled("permissions") then
		print("[SERVER-PERMISSIONS]", ...)
	end
end

export type CastOptions = {
	skillName: string?, -- If provided, allows combo chaining (same skill can re-cast while locked)
	isCombo: boolean?, -- If true and skillName matches locked skill, allow through
}

function Server.new()
	return setmetatable({}, { __index = Server })
end

-- Check if entity can perform specific action
-- options: { skillName?, isCombo? } - for combo chaining support
function Server:canPerformAction(entityId: string, action: string, options: CastOptions?): (boolean, string?)
	-- Check if dead
	local currentHP = StatsManager.getStatValue(entityId, "Health")
	if currentHP and currentHP <= 0 then
		return false, "dead"
	end

	-- Check blocking status effects
	local blocked, reason = StatusEffectsService.hasBlockingEffect(entityId, action)
	debugLog("Blocking check for", entityId, "action:", action, "-> blocked:", blocked, "reason:", reason or "none")
	if blocked then
		return false, reason
	end

	return true
end

-- Convenience methods
-- canCast now accepts options for combo chaining support
function Server:canCast(entityId: string, options: CastOptions?): (boolean, string?)
	return self:canPerformAction(entityId, "cast", options)
end

function Server:canMove(entityId: string): (boolean, string?)
	return self:canPerformAction(entityId, "move")
end

function Server:canJump(entityId: string): (boolean, string?)
	return self:canPerformAction(entityId, "jump")
end

function Server:canDodge(entityId: string): (boolean, string?)
	return self:canPerformAction(entityId, "dodge")
end

function Server:canInteract(entityId: string): (boolean, string?)
	return self:canPerformAction(entityId, "interact")
end

return Server
