--- Handle tagging and registering GUIDs for entities
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Registrar = {}

local idToPlayerMap: { [string]: Player } = {}
local idToEntityMap: { [string]: Model } = {}

function Registrar.registerEntity(entity: Model, isPlayer: boolean?)
	if not entity:FindFirstChild("Humanoid") then
		error("Only Models with Humanoids can be registered as entities.")
	end
	local entityId = HttpService:GenerateGUID()
	entity:SetAttribute("EntityId", entityId)
	CollectionService:AddTag(entity, "Entity")

	if isPlayer then
		local player = Players:GetPlayerFromCharacter(entity)
		if player then
			idToPlayerMap[entityId] = player
		end
	end

	idToEntityMap[entityId] = entity

	return entityId
end

function Registrar.unregisterEntity(entity: Model)
	local entityId = entity:GetAttribute("EntityId")
	if not entityId then
		error("Entity is not registered.")
	end
	CollectionService:RemoveTag(entity, "Entity")
	idToPlayerMap[entityId] = nil
	idToEntityMap[entityId] = nil
end

function Registrar.unregisterEntityById(entityId: string)
	local entity = idToEntityMap[entityId]
	if entity then
		CollectionService:RemoveTag(entity, "Entity")
		idToEntityMap[entityId] = nil
		idToPlayerMap[entityId] = nil
	end
end

function Registrar.unregisterPlayer(player: Player)
	for entityId, registeredPlayer in pairs(idToPlayerMap) do
		if registeredPlayer == player then
			Registrar.unregisterEntityById(entityId)
		end
	end
end

function Registrar.getEntityId(entity: Model): string?
	for entityId, registeredEntity in pairs(idToEntityMap) do
		if registeredEntity == entity then
			return entityId
		end
	end
	return nil
end

function Registrar.getPlayerId(player: Player): string?
	for entityId, registeredPlayer in pairs(idToPlayerMap) do
		if registeredPlayer == player then
			return entityId
		end
	end
	return nil
end

function Registrar.isEntity(entity: Model): boolean
	return entity:GetAttribute("EntityId") ~= nil
end

function Registrar.isPlayerEntity(entityId: string): boolean
	return idToPlayerMap[entityId] ~= nil
end

function Registrar.getPlayerById(entityId: string): Player?
	return idToPlayerMap[entityId]
end

function Registrar.getEntityById(entityId: string): Model?
	return idToEntityMap[entityId]
end

function Registrar.getAllEntities(): { Model }
	local result: { Model } = {}
	for _, entity in pairs(idToEntityMap) do
		table.insert(result, entity)
	end
	return result
end

function Registrar.getAllEntityIds(): { string }
	local result: { string } = {}
	for entityId, _ in pairs(idToEntityMap) do
		table.insert(result, entityId)
	end
	return result
end

return Registrar
