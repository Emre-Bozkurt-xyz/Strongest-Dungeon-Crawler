--!strict
-- LootClient: shows item inspect panel for world drops and handles pickup.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Registry = require(ReplicatedStorage.Shared.items.Registry)
local InventoryClient = require(script.Parent.Parent.Parent.Inventory.InventoryClient)
local InventoryUIController = require(script.Parent.InventoryUIController)

local LootClient = {}

local function buildActions(uid: string)
	return {
		{
			id = "pickup",
			label = "Pick Up",
			enabled = true,
			handler = function()
				InventoryClient.requestAction({
					action = "pickup",
					uid = uid,
				})
			end,
		},
	}
end

local function onPromptShown(prompt: ProximityPrompt, drop: BasePart)
	local uid = drop:GetAttribute("ItemUid")
	local itemId = drop:GetAttribute("ItemId")
	if type(uid) ~= "string" or type(itemId) ~= "string" then
		return
	end
	local def = Registry.get(itemId)
	if not def then
		return
	end
	InventoryUIController.setExternalInspect(def, nil, buildActions(uid))
end

local function onPromptHidden(_prompt: ProximityPrompt)
	InventoryUIController.clearExternalInspect()
end

local function connectDrop(drop: Instance)
	if not drop:IsA("BasePart") then
		return
	end
	local prompt = drop:FindFirstChildWhichIsA("ProximityPrompt", true)
	if not prompt then
		return
	end
	prompt.PromptShown:Connect(function()
		onPromptShown(prompt, drop)
	end)
	prompt.PromptHidden:Connect(function()
		onPromptHidden(prompt)
	end)
end

function LootClient.init()
	for _, inst in ipairs(CollectionService:GetTagged("LootDrop")) do
		connectDrop(inst)
	end
	CollectionService:GetInstanceAddedSignal("LootDrop"):Connect(connectDrop)
end

return LootClient
