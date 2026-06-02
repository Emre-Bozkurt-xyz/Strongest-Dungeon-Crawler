--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)
local ItemInstances = require(script.Parent.Parent.ItemInstances)
local Registry = require(ReplicatedStorage.Shared.items.Registry)
local ItemUtils = require(ReplicatedStorage.Shared.items.ItemUtils)

local InventoryRepository = {}

local inventories: { [string]: ItemTypes.InventoryState? } = {}

function InventoryRepository.ensure(entityId: string, defaultCapacity: number): ItemTypes.InventoryState
	local inv = inventories[entityId]
	if inv then
		return inv
	end
	local slots: { [number]: string? } = {}
	inv = {
		ownerId = entityId,
		capacity = defaultCapacity,
		slots = slots,
		stacks = {},
	}
	for i = 1, defaultCapacity do
		inv.slots[i] = nil
	end
	inventories[entityId] = inv
	return inv
end

function InventoryRepository.get(entityId: string): ItemTypes.InventoryState?
	return inventories[entityId]
end

function InventoryRepository.set(entityId: string, state: ItemTypes.InventoryState)
	inventories[entityId] = state
end

function InventoryRepository.findEmptySlot(inv: ItemTypes.InventoryState): number?
	for i = 1, inv.capacity do
		if inv.slots[i] == nil then
			return i
		end
	end
	return nil
end

function InventoryRepository.rebuildStacks(inv: ItemTypes.InventoryState)
	inv.stacks = {}
	for _, uid in pairs(inv.slots) do
		if uid then
			local inst = ItemInstances.get(uid)
			if inst then
				local def = Registry.get(inst.itemId)
				if def then
					local key = ItemUtils.makeStackKey(inst.itemId, inst.meta, def.stackSensitiveMeta)
					inv.stacks[key] = inv.stacks[key] or {}
					table.insert(inv.stacks[key], uid)
				end
			end
		end
	end
end

return InventoryRepository