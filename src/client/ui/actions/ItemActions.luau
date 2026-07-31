--!strict
-- Item command senders.
--
-- Components call these; they do not build request payloads inline (R10). Keeping the wire format in
-- one place means a change to the inventory protocol touches this file and nothing in the view
-- layer.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryClient = require(script.Parent.Parent.Parent.Inventory.InventoryClient)
local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)
local EquipmentDefUtils = require(ReplicatedStorage.Shared.items.EquipmentDefUtils)

local ItemActions = {}

-- First slot the item accepts that is currently empty, else the first it accepts at all.
--
-- Returning an occupied slot is deliberate: equipping into a full slot is a swap, which the server
-- handles, and refusing to pick one would make "Equip" silently do nothing once a player has
-- something in every valid slot.
function ItemActions.pickEquipSlot(
	def: ItemTypes.ItemDef,
	equipment: ItemTypes.EquipmentState?
): string?
	local slots = EquipmentDefUtils.getEquipSlots(def)
	if not slots or #slots == 0 then
		return nil
	end
	if equipment then
		for _, slot in ipairs(slots) do
			if equipment.slots[slot] == nil then
				return slot
			end
		end
	end
	return slots[1]
end

function ItemActions.equip(fromSlot: number, toSlot: string)
	InventoryClient.requestAction({
		action = "equip",
		fromSlot = fromSlot,
		toSlot = toSlot,
	})
end

function ItemActions.unequip(fromSlot: string)
	InventoryClient.requestAction({
		action = "unequip",
		fromSlot = fromSlot,
		toSlot = nil,
	})
end

function ItemActions.use(uid: string)
	InventoryClient.requestAction({
		action = "use",
		uid = uid,
	})
end

function ItemActions.drop(uid: string)
	InventoryClient.requestAction({
		action = "drop",
		uid = uid,
	})
end

return ItemActions
