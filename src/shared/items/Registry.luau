--!strict
-- Shared registry of ItemDefs.

local ItemTypes = require(script.Parent.ItemTypes)

local Registry = {}

local defs = {
	ManaPotion = require(script.Parent.Defs.ManaPotion),
	IronSword = require(script.Parent.Defs.IronSword),
	LeatherChest = require(script.Parent.Defs.LeatherChest),
}

local byId: { [string]: ItemTypes.ItemDef } = {}

for _, def in pairs(defs) do
	assert(def and type(def) == "table", "Item def must be a table")
	assert(type(def.id) == "string" and def.id ~= "", "Item def missing id")
	byId[def.id] = def
end

function Registry.get(itemId: string): ItemTypes.ItemDef?
	return byId[itemId]
end

function Registry.list(): { ItemTypes.ItemDef }
	local result = {}
	for _, def in pairs(byId) do
		table.insert(result, def)
	end
	table.sort(result, function(a, b)
		return a.id < b.id
	end)
	return result
end

return Registry
