--!strict
-- Shared registry of ItemDefs.

local ItemTypes = require(script.Parent.ItemTypes)

local Registry = {}

local byId: { [string]: ItemTypes.ItemDef } = {}

local function registerDef(def: ItemTypes.ItemDef, sourceName: string)
	assert(def and type(def) == "table", `Item def '{sourceName}' must be a table`)
	assert(type(def.id) == "string" and def.id ~= "", `Item def '{sourceName}' missing id`)
	assert(byId[def.id] == nil, `Duplicate item def id '{def.id}' from '{sourceName}'`)
	byId[def.id] = def
end

local function loadDefModule(module: ModuleScript)
	registerDef(require(module) :: ItemTypes.ItemDef, module:GetFullName())
end

local function loadFlatDefs(folder: Instance?)
	if not folder then
		return
	end
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("ModuleScript") then
			loadDefModule(child)
		end
	end
end

local function loadEquipmentPackages(folder: Instance?)
	if not folder then
		return
	end
	for _, package in ipairs(folder:GetChildren()) do
		if package:IsA("ModuleScript") then
			loadDefModule(package)
		elseif package:IsA("Folder") then
			local init = package:FindFirstChild("init") or package:FindFirstChild("Init")
			if init and init:IsA("ModuleScript") then
				loadDefModule(init)
			end
		end
	end
end

loadEquipmentPackages(script.Parent:FindFirstChild("Equipment"))
loadFlatDefs(script.Parent:FindFirstChild("Defs"))

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
