--!strict
-- Helpers for item stacking and meta-sensitive comparisons.

local ItemUtils = {}

local ItemTypes = require(script.Parent.ItemTypes)

local function buildMetaKey(meta: ItemTypes.ItemMeta?, sensitive: { [string]: boolean }): string
	if not meta then
		return ""
	end
	local keys = {}
	for key in pairs(sensitive) do
		table.insert(keys, key)
	end
	table.sort(keys)
	local parts = {}
	for _, key in ipairs(keys) do
		parts[#parts + 1] = `{key}:{tostring(meta[key])}`
	end
	return table.concat(parts, "|")
end

function ItemUtils.makeStackKey(itemId: string, meta: ItemTypes.ItemMeta?, sensitive: { [string]: boolean }?): string
	if not sensitive or next(sensitive) == nil then
		return itemId
	end
	local metaKey = buildMetaKey(meta, sensitive)
	return if metaKey == "" then itemId else `{itemId}::{metaKey}`
end

function ItemUtils.canStack(metaA: ItemTypes.ItemMeta?, metaB: ItemTypes.ItemMeta?, sensitive: { [string]: boolean }?): boolean
	if not sensitive or next(sensitive) == nil then
		return true
	end
	if metaA == nil and metaB == nil then
		return true
	end
	if metaA == nil or metaB == nil then
		return false
	end
	for key in pairs(sensitive) do
		if metaA[key] ~= metaB[key] then
			return false
		end
	end
	return true
end

return ItemUtils
