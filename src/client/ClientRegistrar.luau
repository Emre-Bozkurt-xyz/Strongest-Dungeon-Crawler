--!strict
-- Client-side entity registry using CollectionService
-- Mirrors server Registrar API but uses EntityId attribute lookups

local CollectionService = game:GetService("CollectionService")

local ClientRegistrar = {}

-- Index for entityId -> Instance lookups
local entityIndex: { [string]: Instance } = {}
local initialized = false

-- Initialize the entity index by listening to "Entity" tag
local function initialize()
	if initialized then
		return
	end
	initialized = true

	-- Index existing entities
	for _, entity in CollectionService:GetTagged("Entity") do
		local entityId = entity:GetAttribute("EntityId")
		if type(entityId) == "string" then
			entityIndex[entityId] = entity
		end
	end

	-- Listen for new entities
	CollectionService:GetInstanceAddedSignal("Entity"):Connect(function(entity)
		local entityId = entity:GetAttribute("EntityId")
		if type(entityId) == "string" then
			entityIndex[entityId] = entity
		end
	end)

	-- Listen for removed entities
	CollectionService:GetInstanceRemovedSignal("Entity"):Connect(function(entity)
		local entityId = entity:GetAttribute("EntityId")
		if type(entityId) == "string" then
			entityIndex[entityId] = nil
		end
	end)
end

-- Get entity Instance by entityId
function ClientRegistrar.getEntity(entityId: string): Instance?
	initialize()

	if not entityId or entityId == "" then
		return nil
	end

	local entity = entityIndex[entityId]
	if entity and entity.Parent then
		return entity
	end

	-- Clean up stale entry
	if entity then
		entityIndex[entityId] = nil
	end

	return nil
end

-- Check if entity is a player entity
function ClientRegistrar.isPlayerEntity(entityId: string): boolean
	initialize()

	local entity = ClientRegistrar.getEntity(entityId)
	if not entity then
		return false
	end

	-- Check if entity or parent is a player character
	local function isPlayerChar(inst: Instance): boolean
		if inst:IsA("Model") then
			local humanoid = inst:FindFirstChild("Humanoid")
			if humanoid then
				local player = game.Players:GetPlayerFromCharacter(inst)
				return player ~= nil
			end
		end
		return false
	end

	if isPlayerChar(entity) then
		return true
	end

	if entity.Parent and isPlayerChar(entity.Parent) then
		return true
	end

	return false
end

-- Get entity by ID (alias for getEntity for compatibility)
function ClientRegistrar.getEntityById(entityId: string): Instance?
	return ClientRegistrar.getEntity(entityId)
end

-- Clear cache entry for an entity (no-op, index is event-driven)
function ClientRegistrar.clearCache(_entityId: string)
	-- No-op: index is automatically maintained by CollectionService listeners
end

-- Clear all cache (no-op, index is event-driven)
function ClientRegistrar.clearAllCache()
	-- No-op: index is automatically maintained by CollectionService listeners
end

return ClientRegistrar
