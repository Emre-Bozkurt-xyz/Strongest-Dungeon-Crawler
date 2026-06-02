--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)

local InventoryCommandService = {}

export type ExecuteFn = (payload: any) -> (boolean, string?)

function InventoryCommandService.execute(entityId: string, command: ItemTypes.InventoryCommand, execute: ExecuteFn): (boolean, string?)
	if command.version ~= 1 then
		return false, "unsupported_version"
	end
	if type(command.action) ~= "string" then
		return false, "invalid_action"
	end

	local payload: any = {
		action = command.action,
	}

	if command.from ~= nil and command.to ~= nil then
		payload.from = command.from
		payload.to = command.to
	end
	if command.uid ~= nil then
		payload.uid = command.uid
	end
	if command.count ~= nil then
		payload.count = command.count
	end
	if command.position ~= nil then
		payload.position = command.position
	end

	if command.action == "split" then
		if not command.from or type(command.from.slot) ~= "number" then
			return false, "invalid_slot"
		end
		payload.fromSlot = command.from.slot
		payload.toSlot = command.to and command.to.slot or nil
	elseif command.action == "merge" then
		if not command.from or not command.to then
			return false, "invalid_slot"
		end
		payload.fromSlot = command.from.slot
		payload.toSlot = command.to.slot
	elseif command.action == "equip" then
		if not command.from or not command.to then
			return false, "invalid_slot"
		end
		payload.fromSlot = command.from.slot
		payload.toSlot = command.to.slot
	elseif command.action == "unequip" then
		if not command.from then
			return false, "invalid_slot"
		end
		payload.fromSlot = command.from.slot
		payload.toSlot = command.to and command.to.slot or nil
	end

	return execute(payload)
end

return InventoryCommandService
