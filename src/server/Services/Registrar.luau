--- Handle tagging and registering GUIDs for entities
--
-- Lookups run in both directions in O(1): hitbox queries resolve an id per candidate model and the
-- entity info tick resolves one per entity per viewer, so a scan here multiplies into every swing.
-- A player owns at most one live entity, and keeps one entity id for their whole session: a new
-- character takes over the id of the one it replaces. Everything keyed by entity id -- inventory,
-- equipment, stats, skills, cooldowns -- belongs to the player, not to one body, and survives a
-- respawn without being carried across.
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Registrar = {}

local idToPlayerMap: { [string]: Player } = {}
local idToEntityMap: { [string]: Model } = {}
local entityToId: { [Model]: string } = {}
local playerToId: { [Player]: string } = {}

function Registrar.unregisterEntityById(entityId: string)
	local entity = idToEntityMap[entityId]
	if entity then
		CollectionService:RemoveTag(entity, "Entity")
		entityToId[entity] = nil
	end
	local player = idToPlayerMap[entityId]
	if player and playerToId[player] == entityId then
		playerToId[player] = nil
	end
	idToEntityMap[entityId] = nil
	idToPlayerMap[entityId] = nil
end

function Registrar.registerEntity(entity: Model, isPlayer: boolean?)
	if not entity:FindFirstChild("Humanoid") then
		error("Only Models with Humanoids can be registered as entities.")
	end
	local player = if isPlayer then Players:GetPlayerFromCharacter(entity) else nil
	local entityId = player and playerToId[player] or HttpService:GenerateGUID()

	-- The body being replaced gives up the id; the id itself stays with the player.
	local previousBody = idToEntityMap[entityId]
	if previousBody and previousBody ~= entity then
		CollectionService:RemoveTag(previousBody, "Entity")
		entityToId[previousBody] = nil
	end

	entity:SetAttribute("EntityId", entityId)
	CollectionService:AddTag(entity, "Entity")

	if player then
		idToPlayerMap[entityId] = player
		playerToId[player] = entityId
	end

	idToEntityMap[entityId] = entity
	entityToId[entity] = entityId

	return entityId
end

function Registrar.unregisterEntity(entity: Model)
	local entityId = entityToId[entity]
	if not entityId then
		error("Entity is not registered.")
	end
	Registrar.unregisterEntityById(entityId)
end

-- Ends the player's session id. Only on leaving: a respawn re-registers under the same id.
function Registrar.unregisterPlayer(player: Player)
	local entityId = playerToId[player]
	if entityId then
		Registrar.unregisterEntityById(entityId)
	end
end

function Registrar.getEntityId(entity: Model): string?
	return entityToId[entity]
end

function Registrar.getPlayerId(player: Player): string?
	return playerToId[player]
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
