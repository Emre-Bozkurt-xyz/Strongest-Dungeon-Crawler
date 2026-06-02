--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Registrar = require(ServerScriptService.Server.Services.Registrar)
local Registry = require(ReplicatedStorage.Shared.items.Registry)
local SharedConfig = require(ReplicatedStorage.Shared.Config)

local LootDropService = {}
local WorldLootInspectConfig = SharedConfig.WorldLootInspect
local SERVER_CONFIG = WorldLootInspectConfig.server

local dropsByUid: { [string]: BasePart } = {}

local function getDropFolder(): Folder
	local folder = Workspace:FindFirstChild("ItemDrops")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "ItemDrops"
		folder.Parent = Workspace
	end
	return folder :: Folder
end

function LootDropService.cleanup(uid: string)
	local part = dropsByUid[uid]
	if part then
		part:Destroy()
	end
	dropsByUid[uid] = nil
end

function LootDropService.get(uid: string): BasePart?
	return dropsByUid[uid]
end

function LootDropService.spawnDrop(
	uid: string,
	itemId: string,
	position: Vector3,
	ownerEntityId: string?,
	display: { displayName: string?, rarity: string?, stackSize: number? }?,
	pickup: (string, string) -> boolean
)
	if dropsByUid[uid] then
		LootDropService.cleanup(uid)
	end

	local def = Registry.get(itemId)
	local part = Instance.new("Part")
	part.Name = "ItemDrop"
	part.Size = Vector3.new(1, 1, 1)
	part.Anchored = true
	part.CanCollide = false
	part.Position = position
	part:SetAttribute("ItemUid", uid)
	part:SetAttribute("ItemId", itemId)
	if ownerEntityId then
		part:SetAttribute("OwnerEntityId", ownerEntityId)
		part:SetAttribute("ClaimExpiresAt", os.clock() + SERVER_CONFIG.claimDuration)
	end
	local displayName = if display and type(display.displayName) == "string" and display.displayName ~= ""
		then display.displayName
		else if def and def.name then def.name else nil
	if type(displayName) == "string" then
		part:SetAttribute("ItemName", displayName)
		part:SetAttribute("ItemDisplayName", displayName)
	end
	if display and type(display.rarity) == "string" then
		part:SetAttribute("ItemRarity", display.rarity)
	end
	if display and type(display.stackSize) == "number" then
		part:SetAttribute("ItemStackSize", display.stackSize)
	end
	part.Parent = getDropFolder()
	CollectionService:AddTag(part, "LootDrop")
	dropsByUid[uid] = part

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pick Up"
	prompt.ObjectText = displayName or "Item"
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = SERVER_CONFIG.pickupDistance
	prompt.Parent = part

	prompt.Triggered:Connect(function(player)
		local entityId = Registrar.getPlayerId(player)
		if not entityId then
			return
		end
		local dropUid = part:GetAttribute("ItemUid")
		if type(dropUid) ~= "string" then
			return
		end
		local ok = pickup(dropUid, entityId)
		if ok then
			LootDropService.cleanup(dropUid)
		end
	end)

	local despawnSeconds = SERVER_CONFIG.despawnSeconds
	if type(despawnSeconds) == "number" and despawnSeconds > 0 then
		task.delay(despawnSeconds, function()
			if dropsByUid[uid] == part then
				LootDropService.cleanup(uid)
			end
		end)
	end
end

return LootDropService
