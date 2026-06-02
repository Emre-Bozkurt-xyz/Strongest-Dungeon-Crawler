--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Networking = require(ReplicatedStorage.Shared.Networking)

local AnimationOverrideStore = {}

local overridesByEntity: { [string]: { [string]: { key: string, overrideKey: string, priority: number? } } } = {}
local localEntityId: string? = nil

local dispatcher = Networking.client()
local dispatcherAny = dispatcher :: any

dispatcherAny:on("InventoryEvent", function(payload: any)
	if type(payload) ~= "table" then
		return
	end
	if payload.kind ~= "projection" or type(payload.projection) ~= "table" then
		return
	end
	local projection = payload.projection
	local entityId = projection.entityId
	if type(entityId) ~= "string" then
		return
	end
	local tableByKey: { [string]: { key: string, overrideKey: string, priority: number? } } = {}
	local entries = projection.animationOverrides
	if type(entries) == "table" then
		for _, entry in ipairs(entries) do
			if type(entry) == "table" and type(entry.key) == "string" and type(entry.overrideKey) == "string" then
				tableByKey[entry.key] = entry
			end
		end
	end
	overridesByEntity[entityId] = tableByKey
end)

function AnimationOverrideStore.setLocalEntityId(entityId: string?)
	localEntityId = entityId
end

function AnimationOverrideStore.resolve(animKey: string, entityId: string?): string
	local lookupId = entityId or localEntityId
	if not lookupId then
		return animKey
	end
	local byKey = overridesByEntity[lookupId]
	if not byKey then
		return animKey
	end
	local entry = byKey[animKey]
	if not entry then
		return animKey
	end
	return entry.overrideKey
end

return AnimationOverrideStore
