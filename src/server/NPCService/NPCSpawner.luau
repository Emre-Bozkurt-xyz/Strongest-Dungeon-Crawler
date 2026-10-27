--!strict
-- NPCSpawner: creates NPC instances using mirrored structure
-- Models: ReplicatedStorage/Assets/NPCPrefabs/<Name>
-- Specs:  ServerScriptService/NPCService/NPCPrefabs/<Name>/NPCSpec (server-only behavior/stats)
-- Visual: ReplicatedStorage/Shared/Characters/NPCs/<Name> (shared CharacterSpec)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ComponentManager = require(script.Parent.ComponentManager)
local NPCAnimationController = require(script.Parent.NPCAnimationController)
local CharacterSpecRegistry = require(ReplicatedStorage.Shared.Characters.CharacterSpecRegistry)

local PREFABS_FOLDER_NAME = "NPCPrefabs"
local ASSETS_ROOT_NAME = "Assets" -- Studio-managed assets root (not controlled by Rojo)
local SPEC_MODULE_NAME = "NPCSpec"

local NPCSpawner = {}

type ComponentHandles = { [string]: any }

local function getAssetsPrefabsFolder(): Folder?
	local assets = ReplicatedStorage:FindFirstChild(ASSETS_ROOT_NAME)
	if assets and assets:IsA("Folder") then
		local assetsPrefabs = assets:FindFirstChild(PREFABS_FOLDER_NAME)
		if assetsPrefabs and assetsPrefabs:IsA("Folder") then
			return assetsPrefabs
		end
	end

	warn("NPCSpawner: Assets/NPCPrefabs not found")
	return nil
end

local function clonePrefab(prefabName: string, debug: boolean?): Model?
	local prefabs = getAssetsPrefabsFolder()
	if not prefabs then
		return nil
	end

	local source = prefabs:FindFirstChild(prefabName)
	if not source then
		warn(`NPCSpawner: Prefab "{prefabName}" missing under Assets/NPCPrefabs`)
		return nil
	end

	local modelSource: Instance? = nil
	if source:IsA("Model") then
		modelSource = source
	elseif source:IsA("Folder") then
		-- Prefer a child model with the same name as the prefab folder; otherwise first model child
		local preferred: Model? = source:FindFirstChild(prefabName) :: Model?
		if preferred and preferred:IsA("Model") then
			modelSource = preferred
		else
			for _, child in ipairs(source:GetChildren()) do
				if child:IsA("Model") then
					modelSource = child
					break
				end
			end
		end
	end

	if not modelSource or not modelSource:IsA("Model") then
		warn(`NPCSpawner: Prefab "{prefabName}" has no Model to clone (found {source.ClassName})`)
		return nil
	end

	if debug then
		print("NPCSpawner: cloning", (modelSource :: Model).Name, "from", source:GetFullName())
	end

	return (modelSource :: Model):Clone()
end

local function tableCopy<T>(input: T): T
	if type(input) ~= "table" then
		return input
	end

	local clone: { [any]: any } = {}
	for key, value in pairs(input) do
		clone[key] = tableCopy(value)
	end

	return clone :: any
end

local function mergeOptions(base: any, overrides: any): any
	if overrides == nil then
		return tableCopy(base)
	end

	if type(base) ~= "table" or type(overrides) ~= "table" then
		return tableCopy(overrides)
	end

	local result = tableCopy(base)
	for key, value in pairs(overrides) do
		if type(value) == "table" and type(result[key]) == "table" then
			result[key] = mergeOptions(result[key], value)
		else
			result[key] = tableCopy(value)
		end
	end

	return result
end

local function readSpecByName(prefabName: string): { [string]: any }
	-- Server-only specs live under this service module hierarchy
	local serverSpecsRoot = script.Parent:FindFirstChild("NPCPrefabs")
	if not serverSpecsRoot or not serverSpecsRoot:IsA("Folder") then
		warn("NPCSpawner: Server NPCPrefabs folder not found (script.Parent.NPCPrefabs)")
		return {}
	end

	local folder = serverSpecsRoot:FindFirstChild(prefabName)
	if not folder or not folder:IsA("Folder") then
		warn(`NPCSpawner: Spec folder missing for "{prefabName}" under NPCService/NPCPrefabs`)
		return {}
	end

	local specModule = folder:FindFirstChild(SPEC_MODULE_NAME)
	if not specModule or not specModule:IsA("ModuleScript") then
		warn(`NPCSpawner: NPCSpec missing for "{prefabName}" under NPCService/NPCPrefabs`)
		return {}
	end

	local ok, spec = pcall(require, specModule)
	if not ok or type(spec) ~= "table" then
		warn(`NPCSpawner: Failed to load NPCSpec for "{prefabName}"`)
		return {}
	end

	return (type(spec.components) == "table") and spec.components or spec
end

local function applyTransform(model: Model, options: { [string]: any }, marker: Instance?)
	if options.cframe then
		model:PivotTo(options.cframe)
		return
	end

	if options.position then
		model:PivotTo(CFrame.new(options.position))
		return
	end

	if marker then
		if marker:IsA("BasePart") then
			model:PivotTo(marker.CFrame)
		elseif marker:IsA("Attachment") then
			model:PivotTo(marker.WorldCFrame)
		end
	end
end

local function resolveParent(explicitParent: Instance?, fallback: Instance?): Instance
	if explicitParent and explicitParent:IsDescendantOf(game) then
		return explicitParent
	end

	if fallback and fallback:IsDescendantOf(game) then
		return fallback
	end

	return Workspace
end

-- What fighting this NPC teaches, as attributes on the model for MasteryService and
-- CharacterService to read. A placeholder until area level, enemy type and rank exist
-- (docs/planning/progression-direction.md, "Character XP from enemies"):
--   progression = { masteryValue = 40 }  -- mastery XP for removing all of its health
--   progression = { xp = 12 }            -- character XP for killing it, shared by contribution
--   progression = { training = true }    -- a training target: flat training XP only
local function applyProgression(model: Model, specOptions: { [string]: any })
	local progression = specOptions.progression
	if type(progression) ~= "table" then
		return
	end
	if type(progression.masteryValue) == "number" then
		model:SetAttribute("MasteryValue", progression.masteryValue)
	end
	if type(progression.xp) == "number" then
		model:SetAttribute("XPValue", progression.xp)
	end
	if progression.training == true then
		model:SetAttribute("TrainingTarget", true)
	end
end

-- What NPCDeath needs when this NPC's health runs out: whether it dies at all (`immortal` in the
-- spec: it resets instead, like a training dummy), and where and after how long it comes back
-- (`respawnDelay` in the spawn options; without one it does not).
local function applyLifecycle(model: Model, specOptions: { [string]: any }, settings: { [string]: any })
	if specOptions.immortal == true then
		model:SetAttribute("Immortal", true)
	end
	if type(settings.respawnDelay) == "number" then
		model:SetAttribute("RespawnDelay", settings.respawnDelay)
		model:SetAttribute("SpawnCFrame", model:GetPivot())
	end
end

local function attachComponents(
	model: Model,
	prefabName: string,
	specOptions: { [string]: any },
	overrides: { [string]: any }?
): ComponentHandles?
	local merged = mergeOptions(specOptions, overrides or {})
	local handles = ComponentManager.attachStandardSet(model, merged)

	-- Register NPC animations from shared CharacterSpec (visual assets live there)
	local sharedSpec = CharacterSpecRegistry.get(prefabName)
	local animSpec = sharedSpec and sharedSpec.animations
	if type(animSpec) == "table" then
		NPCAnimationController.registerNPC(model, animSpec)
	end

	return handles
end

function NPCSpawner.spawn(prefabName: string, options: { [string]: any }?): (Model?, ComponentHandles?)
	local settings = (options or {}) :: { [string]: any }
	local clone = clonePrefab(prefabName, settings.debug)
	if not clone then
		return nil, nil
	end

	-- Store the spec ID as an attribute for client-side lookups
	clone:SetAttribute("CharacterSpecId", prefabName)

	clone.Parent = resolveParent(settings.parent, clone.Parent)
	applyTransform(clone, settings, nil)

	if settings.debug then
		print("NPCSpawner: parented to", clone.Parent and clone.Parent:GetFullName() or "nil")
		local hasParts = false
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("BasePart") then
				hasParts = true
				break
			end
		end
		if not hasParts then
			warn("NPCSpawner: cloned model has no BaseParts; it may be invisible")
		end
	end

	local specOptions = readSpecByName(prefabName)
	applyProgression(clone, specOptions)
	applyLifecycle(clone, specOptions, settings)
	local handles = attachComponents(clone, prefabName, specOptions, settings.components)

	return clone, handles
end

function NPCSpawner.spawnAtMarker(
	marker: Instance,
	prefabName: string,
	options: { [string]: any }?
): (Model?, ComponentHandles?)
	local settings = (options or {}) :: { [string]: any }
	local clone = clonePrefab(prefabName, settings.debug)
	if not clone then
		return nil, nil
	end

	-- Store the spec ID as an attribute for client-side lookups
	clone:SetAttribute("CharacterSpecId", prefabName)

	local parent = settings.parent
	if not parent and marker then
		parent = marker.Parent
	end

	clone.Parent = resolveParent(parent, clone.Parent)
	applyTransform(clone, settings, marker)

	if settings.debug then
		print("NPCSpawner: parented to", clone.Parent and clone.Parent:GetFullName() or "nil", "via marker")
	end

	local specOptions = readSpecByName(prefabName)
	applyProgression(clone, specOptions)
	applyLifecycle(clone, specOptions, settings)
	local handles = attachComponents(clone, prefabName, specOptions, settings.components)

	return clone, handles
end

return NPCSpawner
