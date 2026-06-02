--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)
local EquipmentService = require(script.Parent.Parent.EquipmentService)

local EquipmentRepository = {}

function EquipmentRepository.ensure(entityId: string): ItemTypes.EquipmentState
	return EquipmentService.ensure(entityId)
end

function EquipmentRepository.get(entityId: string): ItemTypes.EquipmentState?
	return EquipmentService.get(entityId)
end

function EquipmentRepository.setSlot(entityId: string, slot: string, uid: string?)
	EquipmentService.setSlot(entityId, slot, uid)
end

function EquipmentRepository.canEquip(itemId: string, slot: string): boolean
	return EquipmentService.canEquip(itemId, slot)
end

function EquipmentRepository.onSlotChanged(callback: (ownerId: string, slot: string, uid: string?) -> ())
	return EquipmentService.onSlotChanged(callback)
end

return EquipmentRepository
