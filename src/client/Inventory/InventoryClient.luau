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
local projection: ItemTypes.EquipmentProjectionSnapshot? = nil

local changeSignal = Instance.new("BindableEvent")

type ChangeContext = {
	kind: "snapshot" | "delta" | "projection",
	delta: ItemTypes.InventoryDelta?,
	projection: ItemTypes.EquipmentProjectionSnapshot?,
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

dispatcherAny:on("InventoryEvent", function(event: ItemTypes.InventoryEvent)
	if type(event) ~= "table" then
		return
	end
	if event.kind == "snapshot" and event.snapshot ~= nil then
		items = event.snapshot.items or {}
		inventory = event.snapshot.inventory
		equipment = event.snapshot.equipment
		notifyChange({ kind = "snapshot", delta = nil, projection = nil })
	elseif event.kind == "delta" and event.delta ~= nil then
		applyDelta(event.delta)
		notifyChange({ kind = "delta", delta = event.delta, projection = nil })
	elseif event.kind == "projection" and event.projection ~= nil then
		projection = event.projection
		notifyChange({ kind = "projection", delta = nil, projection = projection })
	end
end)

function InventoryClient.requestSnapshot()
	local ok, payload = pcall(function()
		return dispatcherAny:request("InventoryRequest", {
			version = 1,
			kind = "snapshot",
		} :: ItemTypes.InventoryRequest)
	end)
	if not ok then
		warn("InventoryClient: snapshot request failed:", payload)
		return
	end
	if type(payload) ~= "table" or payload.snapshot == nil then
		warn("InventoryClient: received nil snapshot")
		return
	end
	local snapshot = payload.snapshot :: ItemTypes.InventorySnapshot
	items = snapshot.items or {}
	inventory = snapshot.inventory
	equipment = snapshot.equipment
	notifyChange({ kind = "snapshot", delta = nil, projection = nil })
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

function InventoryClient.getProjection(): ItemTypes.EquipmentProjectionSnapshot?
	return projection
end

function InventoryClient.requestAction(payload: any): { ok: boolean, error: string? }?
	local ok, response = pcall(function()
		local command: ItemTypes.InventoryCommand = {
			version = 1,
			action = payload.action,
			from = payload.from,
			to = payload.to,
			uid = payload.uid,
			count = payload.count,
			position = payload.position,
		}
		if payload.fromSlot ~= nil then
			local container = if payload.action == "unequip" then "equipment" else "inventory"
			command.from = { container = container, slot = payload.fromSlot }
		end
		if payload.toSlot ~= nil then
			local container = if payload.action == "equip" then "equipment" else "inventory"
			command.to = { container = container, slot = payload.toSlot }
		end
		return dispatcherAny:request("InventoryCommand", command)
	end)
	if not ok then
		warn("InventoryClient: InventoryCommand failed:", response)
		return nil
	end
	return response
end

return InventoryClient
