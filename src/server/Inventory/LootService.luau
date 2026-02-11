--!strict
-- LootService: simple world drop + pickup flow.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Registrar = require(ServerScriptService.Server.Services.Registrar)
local ItemInstances = require(script.Parent.ItemInstances)
local Registry = require(ReplicatedStorage.Shared.items.Registry)

local LootService = {}
local dropsByUid: { [string]: BasePart } = {}
local pickupHandler: ((uid: string, entityId: string) -> boolean)? = nil

function LootService.setPickupHandler(handler: (uid: string, entityId: string) -> boolean)
	pickupHandler = handler
end

local function getDropFolder(): Folder
	local folder = Workspace:FindFirstChild("ItemDrops")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "ItemDrops"
		folder.Parent = Workspace
	end
	return folder :: Folder
end

local function cleanupDrop(uid: string)
	local part = dropsByUid[uid]
	if part then
		part:Destroy()
	end
	dropsByUid[uid] = nil
end

local function attachPrompt(drop: BasePart, ownerEntityId: string?)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pick Up"
	prompt.ObjectText = "Item"
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 8
	prompt.Parent = drop

	prompt.Triggered:Connect(function(player)
		local entityId = Registrar.getPlayerId(player)
		if not entityId then
			return
		end
		if ownerEntityId and ownerEntityId ~= entityId then
			return
		end
		local uid = drop:GetAttribute("ItemUid")
		if type(uid) ~= "string" then
			return
		end
		LootService.pickup(uid, entityId)
	end)
end

function LootService.spawnDrop(uid: string, position: Vector3, ownerEntityId: string?)
	local inst = ItemInstances.get(uid)
	if not inst then
		return
	end
	local def = Registry.get(inst.itemId)
	local dropFolder = getDropFolder()

	if dropsByUid[uid] then
		cleanupDrop(uid)
	end

	local part = Instance.new("Part")
	part.Name = "ItemDrop"
	part.Size = Vector3.new(1, 1, 1)
	part.Anchored = true
	part.CanCollide = false
	part.Position = position
	part:SetAttribute("ItemUid", uid)
	part:SetAttribute("ItemId", inst.itemId)
	if ownerEntityId then
		part:SetAttribute("OwnerEntityId", ownerEntityId)
	end
	if def and def.name then
		part:SetAttribute("ItemName", def.name)
	end
	part.Parent = dropFolder
	CollectionService:AddTag(part, "LootDrop")
	dropsByUid[uid] = part

	attachPrompt(part, ownerEntityId)
end

function LootService.pickup(uid: string, entityId: string): boolean
	local drop = dropsByUid[uid]
	if not drop then
		return false
	end
	local inst = ItemInstances.get(uid)
	if not inst then
		cleanupDrop(uid)
		return false
	end
	local ownerEntityId = drop:GetAttribute("OwnerEntityId")
	if type(ownerEntityId) == "string" and ownerEntityId ~= entityId then
		return false
	end
	if not pickupHandler then
		warn("LootService: pickup handler not registered")
		return false
	end
	local ok = pickupHandler(uid, entityId)
	if ok then
		cleanupDrop(uid)
	end
	return ok
end

return LootService
