--!strict
-- Client-side inventory mirror.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function getNetworkingModule(): ModuleScript
	local shared = ReplicatedStorage:WaitForChild("Shared")
	local networking = shared:FindFirstChild("Networking")
	if networking and networking:IsA("ModuleScript") then
		return networking
	end
	if networking then
		local initModule = networking:FindFirstChild("init") or networking:FindFirstChild("Networking")
		if initModule and initModule:IsA("ModuleScript") then
			return initModule
		end
	end
	error("InventoryClient: Shared.Networking module not found; check Rojo sync/mapping")
end

local Networking = require(getNetworkingModule())
local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)

local dispatcher = Networking.client()
local dispatcherAny = dispatcher :: any

local InventoryClient = {}

local items: { [string]: ItemTypes.ItemInstance } = {}
local inventory: ItemTypes.InventoryState? = nil
local equipment: ItemTypes.EquipmentState? = nil

local changeSignal = Instance.new("BindableEvent")

type ChangeContext = {
	kind: "snapshot" | "delta",
	delta: ItemTypes.InventoryDelta?,
}

local function notifyChange(context: ChangeContext)
	changeSignal:Fire(context)
end

local function ensureInventory(capacity: number)
	if not inventory then
		inventory = {
			ownerId = "",
			capacity = capacity,
			slots = {},
			stacks = {},
		}
	end
	inventory.capacity = capacity
	for i = 1, capacity do
		if inventory.slots[i] == nil then
			inventory.slots[i] = nil
		end
	end
end

local function ensureEquipment()
	if not equipment then
		equipment = {
			ownerId = "",
			slots = {},
		}
	end
end

local function applyDelta(delta: ItemTypes.InventoryDelta)
	if delta.kind == "item_added" then
		items[delta.item.uid] = delta.item
	elseif delta.kind == "item_updated" then
		items[delta.item.uid] = delta.item
	elseif delta.kind == "item_removed" then
		items[delta.uid] = nil
	elseif delta.kind == "inventory_capacity" then
		ensureInventory(delta.capacity)
	elseif delta.kind == "inventory_slot" then
		local currentCap = if inventory then inventory.capacity else 0
		ensureInventory(math.max(currentCap, delta.slot))
		if inventory then
			inventory.slots[delta.slot] = delta.uid
		end
	elseif delta.kind == "equipment_slot" then
		ensureEquipment()
		if equipment then
			equipment.slots[delta.slot] = delta.uid
		end
	end
end

local function onInventoryDelta(delta: ItemTypes.InventoryDelta)
	if not inventory and delta.kind ~= "inventory_capacity" then
		InventoryClient.requestSnapshot()
	end
	applyDelta(delta)
	notifyChange({ kind = "delta", delta = delta })
end

dispatcherAny:on("InventoryDelta", onInventoryDelta)

function InventoryClient.requestSnapshot()
	local ok, payload = pcall(function()
		return dispatcherAny:request("InventoryRequest", {})
	end)
	if not ok then
		warn("InventoryClient: snapshot request failed:", payload)
		return
	end
	if payload == nil then
		warn("InventoryClient: received nil snapshot")
		return
	end
	items = payload.items or {}
	inventory = payload.inventory
	equipment = payload.equipment
	notifyChange({ kind = "snapshot" })
end

function InventoryClient.getInventory(): ItemTypes.InventoryState?
	return inventory
end

function InventoryClient.getEquipment(): ItemTypes.EquipmentState?
	return equipment
end

function InventoryClient.getItem(uid: string): ItemTypes.ItemInstance?
	return items[uid]
end

function InventoryClient.getItems(): { [string]: ItemTypes.ItemInstance }
	return items
end

function InventoryClient.onChanged(callback: (ChangeContext) -> ()): () -> ()
	local connection = changeSignal.Event:Connect(function(context)
		callback(context)
	end)
	return function()
		if connection.Connected then
			connection:Disconnect()
		end
	end
end

function InventoryClient.requestAction(payload: any): { ok: boolean, error: string? }?
	local ok, response = pcall(function()
		return dispatcherAny:request("InventoryAction", payload)
	end)
	if not ok then
		warn("InventoryClient: InventoryAction failed:", response)
		return nil
	end
	return response
end

return InventoryClient
