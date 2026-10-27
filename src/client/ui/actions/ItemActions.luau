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
local NotificationClient = require(script.Parent.Parent.controllers.NotificationClient)

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

-- Gear requirements are hard (server: RequirementEvaluator), so an equip below them is refused;
-- the player is told which one, whichever view sent it.
local function explainRefusal(reason: string?)
	local requirement = reason and string.match(reason, "^requirement_failed::(.+)$")
	if not requirement then
		return
	end
	NotificationClient.push({
		tag = "CANNOT EQUIP",
		tone = "warning",
		text = if requirement == "Level" then "LEVEL TOO LOW" else `NOT ENOUGH {string.upper(requirement)}`,
		key = `equip-refused:{requirement}`,
	})
end

function ItemActions.equip(fromSlot: number, toSlot: string)
	task.spawn(function()
		local response = InventoryClient.requestAction({
			action = "equip",
			fromSlot = fromSlot,
			toSlot = toSlot,
		})
		if response and not response.ok then
			explainRefusal(response.error)
		end
	end)
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

-- `uid` is the dropped item's, read off the LootDrop part. Range is enforced server-side.
-- Yields for the server's answer, so the caller can say what happened.
function ItemActions.pickup(uid: string): { ok: boolean, error: string? }?
	return InventoryClient.requestAction({
		action = "pickup",
		uid = uid,
	})
end

return ItemActions
