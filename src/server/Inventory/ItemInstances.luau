--!strict
-- Server-side item instance storage.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)
local Registry = require(ReplicatedStorage.Shared.items.Registry)
local EquipmentRollService = require(script.Parent.Generation.EquipmentRollService)

local ItemInstances = {}

local itemsByUid: { [string]: ItemTypes.ItemInstance } = {}

local function newUid(): string
	return HttpService:GenerateGUID(false)
end

function ItemInstances.create(itemId: string, stackSize: number, meta: ItemTypes.ItemMeta?): ItemTypes.ItemInstance?
	local def = Registry.get(itemId)
	if not def then
		return nil
	end
	local size = math.max(1, stackSize)
	if def.stackLimit and def.stackLimit > 0 then
		size = math.min(size, def.stackLimit)
	end
	local metaCopy: ItemTypes.ItemMeta = meta and table.clone(meta) or {}
	if def.metadata then
		if def.metadata.chargesMax ~= nil and metaCopy.chargesMax == nil then
			metaCopy.chargesMax = def.metadata.chargesMax
		end
		if def.metadata.chargesConsumed ~= nil and metaCopy.chargesConsumed == nil then
			metaCopy.chargesConsumed = def.metadata.chargesConsumed
		end
		if def.metadata.chargesMax ~= nil and metaCopy.chargesCurrent == nil then
			metaCopy.chargesCurrent = def.metadata.chargesMax
		end
	end
	metaCopy = EquipmentRollService.prepareMeta(def, metaCopy) or metaCopy
	local instance: ItemTypes.ItemInstance = {
		uid = newUid(),
		itemId = itemId,
		stackSize = size,
		meta = if next(metaCopy) ~= nil then metaCopy else nil,
	}
	itemsByUid[instance.uid] = instance
	return instance
end

-- Bring back an item from a save, under its saved uid and with its saved meta: unlike `create`, no
-- rolls and no defaults, since those were applied when the item was first made. Nil when the item
-- no longer exists in the game (its definition was removed).
function ItemInstances.restore(
	uid: string,
	itemId: string,
	stackSize: number,
	meta: ItemTypes.ItemMeta?
): ItemTypes.ItemInstance?
	local def = Registry.get(itemId)
	if not def then
		return nil
	end
	local size = math.max(1, math.floor(stackSize))
	if def.stackLimit and def.stackLimit > 0 then
		size = math.min(size, def.stackLimit)
	end
	local instance: ItemTypes.ItemInstance = {
		uid = uid,
		itemId = itemId,
		stackSize = size,
		meta = if meta and next(meta) ~= nil then meta else nil,
	}
	itemsByUid[uid] = instance
	return instance
end

function ItemInstances.get(uid: string): ItemTypes.ItemInstance?
	return itemsByUid[uid]
end

function ItemInstances.update(uid: string, fields: { [string]: any }): ItemTypes.ItemInstance?
	local item = itemsByUid[uid]
	if not item then
		return nil
	end
	for key, value in pairs(fields) do
		(item :: any)[key] = value
	end
	return item
end

function ItemInstances.remove(uid: string): ItemTypes.ItemInstance?
	local item = itemsByUid[uid]
	if item then
		itemsByUid[uid] = nil
	end
	return item
end

function ItemInstances.list(): { ItemTypes.ItemInstance }
	local result = {}
	for _, item in pairs(itemsByUid) do
		table.insert(result, item)
	end
	return result
end

return ItemInstances
