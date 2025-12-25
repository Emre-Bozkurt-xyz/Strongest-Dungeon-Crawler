--!strict
-- Character Spec Registry - Central registry for loading character specs

local Types = require(script.Parent.Types)

local CharacterSpecRegistry = {}

-- Loaded specs cache
local specs: { [string]: Types.CharacterSpec } = {}

-- Preload common specs
local function preloadSpecs()
	-- Player character
	local PlayerCharacter = require(script.Parent.PlayerCharacter)
	specs[PlayerCharacter.id] = PlayerCharacter

	-- TODO: Preload common NPC specs here
	-- local Goblin = require(script.Parent.NPCs.Goblin)
	-- specs[Goblin.id] = Goblin
end

-- Get spec by ID (loads on demand if not cached)
function CharacterSpecRegistry.get(specId: string): Types.CharacterSpec?
	-- Return cached if available
	if specs[specId] then
		return specs[specId]
	end

	-- Try to load from NPCs folder
	local NPCs = script.Parent:FindFirstChild("NPCs")
	if NPCs then
		local specModule = NPCs:FindFirstChild(specId)
		if specModule and specModule:IsA("ModuleScript") then
			local success, spec = pcall(require, specModule)
			if success and type(spec) == "table" then
				specs[specId] = spec :: Types.CharacterSpec
				return specs[specId]
			else
				warn(`[CharacterSpecRegistry] Failed to load spec: {specId}`)
			end
		end
	end

	warn(`[CharacterSpecRegistry] Spec not found: {specId}`)
	return nil
end

-- Get all loaded specs
function CharacterSpecRegistry.getAll(): { [string]: Types.CharacterSpec }
	return table.clone(specs)
end

-- Check if spec exists
function CharacterSpecRegistry.has(specId: string): boolean
	return specs[specId] ~= nil
end

-- Initialize registry
preloadSpecs()

return CharacterSpecRegistry
