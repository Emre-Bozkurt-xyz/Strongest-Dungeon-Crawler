--!strict
-- ComponentManager: Orchestrates component updates without circular dependencies
-- This breaks the cycle between NPCManager and individual components

local NPCManager = require(script.Parent.NPCManager)
local Components = script.Parent.Components
local Movement = require(Components.Movement)
local Combat = require(Components.Combat)
local Behavior = require(Components.Behavior)
local Damageable = require(Components.Damageable)

local ComponentManager = {}

-- Re-export NPCManager functions for components to use
ComponentManager.hasComponent = NPCManager.hasComponent
ComponentManager.getComponent = NPCManager.getComponent
ComponentManager.addComponent = NPCManager.addComponent
ComponentManager.removeComponent = NPCManager.removeComponent
ComponentManager.getNPCsWithComponent = NPCManager.getNPCsWithComponent
ComponentManager.isNPC = NPCManager.isNPC

-- Initialize component system
function ComponentManager.initialize()
	-- Set manager reference for components
	
	-- Movement and Combat will be updated to have setManager when created
end

export type StandardSetupOptions = {
	movement: Movement.MovementConfig?,
	combat: Combat.CombatConfig?,
	behavior: Behavior.BehaviorConfig?,
	damageable: Damageable.DamageableConfig?,
	skipDamageable: boolean?,
}

function ComponentManager.attachStandardSet(npcModel: Model, options: StandardSetupOptions?)
	local opts: StandardSetupOptions = (options or {}) :: StandardSetupOptions

	if not ComponentManager.isNPC(npcModel) then
		NPCManager.register(npcModel)
	end

	local created = {}

	if opts.skipDamageable ~= true and not ComponentManager.hasComponent(npcModel, "Damageable") then
		created.damageable = Damageable.new(npcModel, opts.damageable)
	end

	if not ComponentManager.hasComponent(npcModel, "Movement") then
		created.movement = Movement.new(npcModel, opts.movement or {})
	end

	if not ComponentManager.hasComponent(npcModel, "Combat") then
		created.combat = Combat.new(npcModel, opts.combat or {})
	end

	if not ComponentManager.hasComponent(npcModel, "Behavior") then
		created.behavior = Behavior.new(npcModel, opts.behavior or {})
	end

	return created
end

-- Update all component systems
function ComponentManager.updateAll(deltaTime: number)

	Behavior.updateAll(deltaTime)
	Movement.updateAll(deltaTime)
	Combat.updateAll(deltaTime)
end

return ComponentManager