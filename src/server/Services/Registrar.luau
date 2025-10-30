--- Handle tagging and registering GUIDs for entities
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")

local Registrar = {}

function Registrar.registerEntity(entity: Model)
	if not entity:FindFirstChild("Humanoid") then
		error("Only Models with Humanoids can be registered as entities.")
	end
	local entityId = HttpService:GenerateGUID()
	entity:SetAttribute("EntityId", entityId)
	CollectionService:AddTag(entity, "Entity")
	return entityId
end

return Registrar
