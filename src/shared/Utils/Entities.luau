local CollectionService = game:GetService("CollectionService")

local Entities = {}

function Entities.getEntityById(entityId: string): Model?
	local entities = CollectionService:GetTagged("Entity")
	for _, entity in ipairs(entities) do
		if entity:GetAttribute("EntityId") == entityId then
			return entity
		end
	end
	return nil
end

function Entities.getAllEntities(): { Model }
	local entities = CollectionService:GetTagged("Entity")
	return entities
end

function Entities.getAllEntityIds(): { string }
	local entityIds: { string } = {}
	local entities = CollectionService:GetTagged("Entity")
	for _, entity in ipairs(entities) do
		local entityId = entity:GetAttribute("EntityId")
		if entityId then
			table.insert(entityIds, entityId)
		end
	end
	return entityIds
end

function Entities.getNearbyEntities(position: Vector3, range: number): { Model }
	local nearbyEntities: { Model } = {}
	local entities = CollectionService:GetTagged("Entity")
	for _, entity in ipairs(entities) do
		if entity.PrimaryPart then
			local distance = (entity.PrimaryPart.Position - position).Magnitude
			if distance <= range then
				table.insert(nearbyEntities, entity)
			end
		end
	end
	return nearbyEntities
end

function Entities.getPlayerEntity(player: Player): Model?
	local character = player.Character
	if character then
		local entityId = character:GetAttribute("EntityId")
		if entityId then
			return Entities.getEntityById(entityId)
		end
	end
	return nil
end

return Entities
