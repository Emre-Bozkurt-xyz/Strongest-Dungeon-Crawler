--!strict
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Registrar = {}

local entityIndex: { [string]: Instance } = {}
local initialized = false

local function initialize()
	if initialized then
		return
	end
	initialized = true

	for _, entity in CollectionService:GetTagged("Entity") do
		local entityId = entity:GetAttribute("EntityId")
		if type(entityId) == "string" and entityId ~= "" then
			entityIndex[entityId] = entity
		end
	end

	CollectionService:GetInstanceAddedSignal("Entity"):Connect(function(entity)
		local entityId = entity:GetAttribute("EntityId")
		if type(entityId) == "string" and entityId ~= "" then
			entityIndex[entityId] = entity
		end
	end)

	CollectionService:GetInstanceRemovedSignal("Entity"):Connect(function(entity)
		local entityId = entity:GetAttribute("EntityId")
		if type(entityId) == "string" and entityId ~= "" then
			entityIndex[entityId] = nil
		end
	end)
end

function Registrar.getEntity(entityId: string): Instance?
	initialize()
	if entityId == "" then
		return nil
	end
	local entity = entityIndex[entityId]
	if entity and entity.Parent then
		return entity
	end
	if entity then
		entityIndex[entityId] = nil
	end
	return nil
end

function Registrar.getEntityById(entityId: string): Instance?
	return Registrar.getEntity(entityId)
end

function Registrar.getEntityId(entity: Instance?): string?
	if not entity then
		return nil
	end
	local entityId = entity:GetAttribute("EntityId")
	if type(entityId) == "string" and entityId ~= "" then
		return entityId
	end
	return nil
end

function Registrar.getLocalPlayerEntity(): Model?
	local player = Players.LocalPlayer
	local char = player and player.Character
	if char and char.Parent then
		return char
	end
	return nil
end

function Registrar.getLocalEntityId(): string?
	local char = Registrar.getLocalPlayerEntity()
	if not char then
		return nil
	end
	return Registrar.getEntityId(char)
end

function Registrar.isPlayerEntity(entityId: string): boolean
	local entity = Registrar.getEntity(entityId)
	if not entity then
		return false
	end
	if entity:IsA("Model") and Players:GetPlayerFromCharacter(entity) then
		return true
	end
	if entity.Parent and entity.Parent:IsA("Model") and Players:GetPlayerFromCharacter(entity.Parent) then
		return true
	end
	return false
end

function Registrar.getPlayerById(entityId: string): Player?
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if char then
			local id = Registrar.getEntityId(char)
			if id == entityId then
				return player
			end
		end
	end
	return nil
end

function Registrar.getAllEntities(): { Instance }
	initialize()
	local result: { Instance } = {}
	for _, entity in pairs(entityIndex) do
		if entity and entity.Parent then
			table.insert(result, entity)
		end
	end
	return result
end

function Registrar.getAllEntityIds(): { string }
	initialize()
	local result: { string } = {}
	for entityId, entity in pairs(entityIndex) do
		if entity and entity.Parent then
			table.insert(result, entityId)
		end
	end
	return result
end

return Registrar
