local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Entities = require(ReplicatedStorage.Shared.Utils.Entities)
local Networking = require(ReplicatedStorage.Shared.Networking)
local FXPlayer = require(script.Parent.FXPlayer)
local Players = game:GetService("Players")

local dispatcher = Networking.client()
dispatcher:_ensureChannel("FXReplicator")

local Replicator = {}

local fxMap: { [string]: { [string]: any } } = {}

--  Note:   server can provide an entityId if it wishes to attach FX to an entity,
--          else entityId will become "Server", anchoring is not possible here.

export type FXEventOptions = {
	fxKey: string,
	entityId: string?,
	origin: Vector3?,
	range: number?,
	anchorName: string?,
	offset: CFrame?,
	lifetime: number?,
	action: string?,
	meta: { [string]: any }?,
}

function Replicator.emitFX(opts: FXEventOptions)
	opts.entityId = Players.LocalPlayer.Character:GetAttribute("EntityId")
	if not opts.entityId then
		warn("FXReplicator: Player character does not have an EntityId attribute.")
		return
	end
	dispatcher:emit("FXEvent", opts)
end

local findAnchor = function(entity: Model, anchorName: string): Attachment?
	local anchor = entity:FindFirstChild(anchorName, true)
	return anchor
end

dispatcher:on("FXEvent", function(payload: FXEventOptions, _meta: any)
	local fxKey = payload.fxKey

	local entityId = payload.entityId
	local entity = entityId and Entities.getEntityById(entityId) or nil

	if not entityId then
		-- Server event
		entityId = "Server"
		return
	end

	if entityId ~= "Server" and payload.anchorName then
		if payload.action == "start" then
			fxMap[entityId] = fxMap[entityId] or {}

			if fxMap[entityId][fxKey] then
				pcall(fxMap[entityId][fxKey].Stop)
			end

			local anchor = findAnchor(entity, payload.anchorName)
			if anchor then
				local handler = FXPlayer.spawnAttached(fxKey, anchor, payload.offset)
				fxMap[entityId][fxKey] = handler
			end
		elseif payload.action == "stop" then
			if fxMap[entityId] and fxMap[entityId][fxKey] then
				pcall(fxMap[entityId][fxKey].Stop)
				fxMap[entityId][fxKey] = nil
			end
		else
			local anchor = findAnchor(entity, payload.anchorName)
			if anchor then
				FXPlayer.playAttached(fxKey, anchor, payload.offset, payload.lifetime)
			end
		end
	else
		if payload.action == "start" then
			fxMap[entityId] = fxMap[entityId] or {}

			if fxMap[entityId][fxKey] then
				pcall(fxMap[entityId][fxKey].Stop)
			end

			local handler = FXPlayer.spawnAt(fxKey, payload.offset or CFrame.new())
			fxMap[entityId][fxKey] = handler
		elseif payload.action == "stop" then
			if fxMap[entityId] and fxMap[entityId][fxKey] then
				pcall(fxMap[entityId][fxKey].Stop)
				fxMap[entityId][fxKey] = nil
			end
		else
			FXPlayer.playAt(fxKey, payload.offset or CFrame.new(), payload.lifetime)
		end
	end
end)

return Replicator
