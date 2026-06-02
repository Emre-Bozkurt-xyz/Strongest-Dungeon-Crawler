--!strict
-- Shared registry of equipment visual profiles.

local ItemTypes = require(script.Parent.ItemTypes)

local VisualProfileRegistry = {}

local byId: { [string]: ItemTypes.EquipmentVisualProfile } = {}

local function registerProfile(profile: ItemTypes.EquipmentVisualProfile, sourceName: string)
	assert(profile and type(profile) == "table", `Visual profile '{sourceName}' must return a table`)
	assert(type(profile.id) == "string" and profile.id ~= "", `Visual profile '{sourceName}' missing id`)
	assert(byId[profile.id] == nil, `Duplicate visual profile id '{profile.id}' from '{sourceName}'`)
	byId[profile.id] = profile
end

local function loadProfileModule(module: ModuleScript)
	registerProfile(require(module) :: ItemTypes.EquipmentVisualProfile, module:GetFullName())
end

local function loadFlatProfiles(folder: Instance?)
	if not folder then
		return
	end
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("ModuleScript") then
			loadProfileModule(child)
		end
	end
end

local function loadPackageProfiles(package: Instance)
	for _, child in ipairs(package:GetChildren()) do
		if child:IsA("ModuleScript") and string.sub(child.Name, 1, 7) == "visual." then
			loadProfileModule(child)
		end
	end
end

local function loadEquipmentPackageProfiles(folder: Instance?)
	if not folder then
		return
	end
	for _, package in ipairs(folder:GetChildren()) do
		if package:IsA("ModuleScript") or package:IsA("Folder") then
			loadPackageProfiles(package)
		end
	end
end

loadEquipmentPackageProfiles(script.Parent:FindFirstChild("Equipment"))
loadFlatProfiles(script.Parent:FindFirstChild("VisualProfiles"))

function VisualProfileRegistry.get(profileId: string): ItemTypes.EquipmentVisualProfile?
	return byId[profileId]
end

function VisualProfileRegistry.list(): { ItemTypes.EquipmentVisualProfile }
	local result = {}
	for _, profile in pairs(byId) do
		table.insert(result, profile)
	end
	table.sort(result, function(a, b)
		return a.id < b.id
	end)
	return result
end

return VisualProfileRegistry
