--!strict
-- Server-side equipment container management.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)
local Registry = require(ReplicatedStorage.Shared.items.Registry)

local EquipmentService = {}

local equipmentByOwner: { [string]: ItemTypes.EquipmentState } = {}
local slotChangedListeners: { (ownerId: string, slot: string, uid: string?) -> () } = {}

local DEFAULT_SLOTS = {
	"Main",
	"Secondary",
	"Head",
	"Neck",
	"Body",
	"Hands",
	"Waist",
	"Feet",
	"Ring1",
	"Ring2",
}

function EquipmentService.ensure(ownerId: string): ItemTypes.EquipmentState
	local equip = equipmentByOwner[ownerId]
	if equip then
		return equip
	end
	local slots: { [string]: string? } = {}
	for _, slot in ipairs(DEFAULT_SLOTS) do
		slots[slot] = nil
	end
	equip = {
		ownerId = ownerId,
		slots = slots,
	}
	equipmentByOwner[ownerId] = equip
	return equip
end

function EquipmentService.get(ownerId: string): ItemTypes.EquipmentState?
	return equipmentByOwner[ownerId]
end

function EquipmentService.canEquip(itemId: string, slot: string): boolean
	local def = Registry.get(itemId)
	if not def then
		return false
	end
	if def.category ~= "equipment" then
		return false
	end
	if not def.equipSlots then
		return false
	end
	for _, s in ipairs(def.equipSlots) do
		if s == slot then
			return true
		end
	end
	return false
end

function EquipmentService.setSlot(ownerId: string, slot: string, uid: string?)
	local equip = EquipmentService.ensure(ownerId)
	equip.slots[slot] = uid
	for _, listener in ipairs(slotChangedListeners) do
		task.spawn(function()
			listener(ownerId, slot, uid)
		end)
	end
end

function EquipmentService.onSlotChanged(callback: (ownerId: string, slot: string, uid: string?) -> ())
	table.insert(slotChangedListeners, callback)
	return function()
		for i, cb in ipairs(slotChangedListeners) do
			if cb == callback then
				table.remove(slotChangedListeners, i)
				break
			end
		end
	end
end

return EquipmentService
