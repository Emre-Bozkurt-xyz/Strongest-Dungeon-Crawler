--!strict
-- NPCManager: Core NPC system using component-based architecture
-- Leverages Roblox native storage (Attributes + Folders) for performance and debugging ease

local RunService = game:GetService("RunService")
local Server = game:GetService("ServerScriptService").Server
local Registrar = require(Server.Services.Registrar)

local StatsManager = require(Server.Stats.StatsManager)

type StatsRegisterOptions = StatsManager.RegisterOptions
export type RegisterOptions = StatsRegisterOptions & {
	skipStats: boolean?,
}

local NPCManager = {}

-- Active NPCs registry: Model -> NPCInstance
local activeNPCs: { [Model]: any } = {}

-- Component system helpers using Roblox native storage
local function getOrCreateComponentFolder(npcModel: Model, componentName: string): Folder
	local components = npcModel:FindFirstChild("Components")
	if not components or not components:IsA("Folder") then
		local newComponents = Instance.new("Folder")
		newComponents.Name = "Components"
		newComponents.Parent = npcModel
		components = newComponents
	end
	local componentsFolder = components :: Folder

	local component = componentsFolder:FindFirstChild(componentName)
	if not component or not component:IsA("Folder") then
		local newComponent = Instance.new("Folder")
		newComponent.Name = componentName
		newComponent.Parent = componentsFolder
		component = newComponent
	end

	return component :: Folder
end

-- Check if an NPC has a specific component
function NPCManager.hasComponent(npcModel: Model, componentName: string): boolean
	local components = npcModel:FindFirstChild("Components")
	if not components then
		return false
	end

	local component = components:FindFirstChild(componentName)
	return component ~= nil and (component:GetAttribute("__active") == true)
end

-- Get component folder for external component systems to store data
function NPCManager.getComponent(npcModel: Model, componentName: string): Folder?
	if not NPCManager.hasComponent(npcModel, componentName) then
		return nil
	end

	local components = npcModel:FindFirstChild("Components")
	if not components then
		return nil
	end
	local comp = components:FindFirstChild(componentName)
	if comp and comp:IsA("Folder") then
		return comp
	end
	return nil
end

-- Add a component to an NPC (marks as active)
function NPCManager.addComponent(npcModel: Model, componentName: string): Folder
	local component = getOrCreateComponentFolder(npcModel, componentName)
	component:SetAttribute("__active", true)
	component:SetAttribute("__addedAt", os.clock())
	return component
end

-- Remove a component from an NPC
function NPCManager.removeComponent(npcModel: Model, componentName: string): boolean
	local components = npcModel:FindFirstChild("Components")
	if not components then
		return false
	end

	local component = components:FindFirstChild(componentName)
	if component then
		component:SetAttribute("__active", false)
		return true
	end
	return false
end

-- Get all active components for an NPC
function NPCManager.getActiveComponents(npcModel: Model): { string }
	local activeComponents = {}
	local components = npcModel:FindFirstChild("Components")
	if not components then
		return activeComponents
	end

	for _, component in pairs(components:GetChildren()) do
		if component:IsA("Folder") and component:GetAttribute("__active") == true then
			table.insert(activeComponents, component.Name)
		end
	end

	return activeComponents
end

function NPCManager.register(npcModel: Model, options: RegisterOptions?): boolean
	if activeNPCs[npcModel] then
		warn(`NPC {npcModel.Name} is already registered`)
		return false
	end

	local entityId = Registrar.registerEntity(npcModel)

	-- Basic validation
	local humanoid = npcModel:FindFirstChild("Humanoid")
	-- Allow registration even if no humanoid (for extensibility)
	local npcInstance = {
		model = npcModel,
		entityId = entityId,
		humanoid = humanoid,
		registeredAt = os.clock(),
		lastUpdate = 0,
	}

	activeNPCs[npcModel] = npcInstance

	if not (options and options.skipStats) then
		local statsOptions: StatsRegisterOptions = {
			stats = options and options.stats or nil,
			configure = options and options.configure or nil,
			skipSync = true,
		}
		StatsManager.register(entityId, statsOptions)
	end

	-- Mark model as managed NPC
	npcModel:SetAttribute("__isNPC", true)
	npcModel:SetAttribute("__registeredAt", os.clock())

	print(`Registered NPC: {npcModel.Name}`)
	return true
end

-- Unregister an NPC (cleanup)
function NPCManager.unregister(npcModel: Model): boolean
	local npcInstance = activeNPCs[npcModel]
	if not npcInstance then
		return false
	end

	local entityId = npcInstance.entityId

	activeNPCs[npcModel] = nil
	npcModel:SetAttribute("__isNPC", nil)

	if StatsManager.isRegistered(entityId) then
		StatsManager.unregister(entityId)
	end

	Registrar.unregisterEntity(entityId)

	print(`Unregistered NPC: {npcModel.Name}`)
	return true
end

-- Get NPC instance data
function NPCManager.getInstance(npcModel: Model): any?
	return activeNPCs[npcModel]
end

-- Check if model is a managed NPC
function NPCManager.isNPC(model: Model): boolean
	return model:GetAttribute("__isNPC") == true
end

-- Get all active NPCs
function NPCManager.getAllNPCs(): { [Model]: any }
	return activeNPCs
end

-- Get NPCs with specific component
function NPCManager.getNPCsWithComponent(componentName: string): { Model }
	local results = {}
	for npcModel, _ in pairs(activeNPCs) do
		if NPCManager.hasComponent(npcModel, componentName) then
			table.insert(results, npcModel)
		end
	end
	return results
end

-- Main update loop (will be called by RunService)
local function updateNPCs(_deltaTime: number)
	local currentTime = os.clock()

	for npcModel, npcInstance in pairs(activeNPCs) do
		-- Basic validation - remove if model destroyed
		if not npcModel.Parent then
			NPCManager.unregister(npcModel)
			continue
		end

		-- Update timing
		npcInstance.lastUpdate = currentTime
	end

	-- Component updates will be handled externally to avoid circular dependencies
	-- The main server script will call ComponentManager.updateAll()
end

-- Initialize the NPC system
function NPCManager.initialize()
	-- Hook into game update loop
	RunService.Heartbeat:Connect(updateNPCs)

	-- Clean up NPCs when they're removed from workspace
	workspace.ChildRemoved:Connect(function(child)
		if child:IsA("Model") and NPCManager.isNPC(child) then
			NPCManager.unregister(child)
		end
	end)

	print("NPCManager initialized")
end

-- Shutdown cleanup
function NPCManager.shutdown()
	for npcModel, _ in pairs(activeNPCs) do
		NPCManager.unregister(npcModel)
	end
	print("NPCManager shutdown")
end

return NPCManager
