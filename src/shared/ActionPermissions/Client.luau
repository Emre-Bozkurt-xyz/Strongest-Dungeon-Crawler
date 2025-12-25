--!strict
-- ActionPermissions Client - Mirrors session state and status effects for local permission checks

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Networking = require(ReplicatedStorage.Shared.Networking)

local Client = {}

local blockingEffects: { [string]: { [string]: boolean } } = {} -- entityId -> action -> blocked

export type CastOptions = {
	skillName: string?,
	isCombo: boolean?,
}

function Client.new(sessionMirror: any?)
	local self = setmetatable({
		_sessionMirror = sessionMirror,
	}, { __index = Client })

	local dispatcher = Networking.client()

	-- Listen to status effect blocking updates (emitted by StatusEffectsService)
	-- NOTE: do not WaitForChild the RemoteEvent directly; the dispatcher ensures the channel
	-- using ReplicatedStorage.NetworkChannels.
	dispatcher:on("StatusEffectBlocking", function(event: any)
		local entityId = event.entityId
		if not blockingEffects[entityId] then
			blockingEffects[entityId] = {}
		end

		if event.action == "all" then
			-- Effect blocks all actions
			for _, action in { "cast", "move", "jump", "dodge", "interact" } do
				blockingEffects[entityId][action] = event.blocked
			end
		else
			blockingEffects[entityId][event.action] = event.blocked
		end
	end)

	return self
end

function Client:setSessionMirror(sessionMirror: any?)
	self._sessionMirror = sessionMirror
end

-- Check if entity can perform specific action (local mirror)
function Client:canPerformAction(entityId: string?, action: string, options: CastOptions?): (boolean, string?)
	if type(entityId) ~= "string" or entityId == "" then
		return false, "unknown_entity"
	end

	-- Check execution lock (blocks cast)
	if action == "cast" then
		local mirror = self._sessionMirror
		if mirror and mirror.getSession then
			local session = mirror.getSession(entityId)
			if session and session.state ~= "COMPLETED" and session.state ~= "CANCELLED" then
				local opts = options or {}
				if opts.isCombo and opts.skillName and session.skillId == opts.skillName then
					-- Combo chaining allowed - same skill can re-cast
				else
					return false, "executing_skill"
				end
			end
		end
	end

	-- Check blocking effects
	if blockingEffects[entityId] and blockingEffects[entityId][action] then
		return false, "blocked"
	end

	return true
end

-- Convenience methods
function Client:canCast(entityId: string, options: CastOptions?): (boolean, string?)
	return self:canPerformAction(entityId, "cast", options)
end

function Client:canMove(entityId: string): (boolean, string?)
	return self:canPerformAction(entityId, "move")
end

function Client:canJump(entityId: string): (boolean, string?)
	return self:canPerformAction(entityId, "jump")
end

function Client:canDodge(entityId: string): (boolean, string?)
	return self:canPerformAction(entityId, "dodge")
end

function Client:canInteract(entityId: string): (boolean, string?)
	return self:canPerformAction(entityId, "interact")
end

return Client
