--!strict
-- ModifierRegistry: Per-entity storage for attack/skill modifiers
-- Modifiers transform queries in the AttackResolver pipeline
-- Supports priority-ordered application for deterministic results

local ModifierRegistry = {}

-- Type definitions
export type ModifierFunction = (ctx: any, result: any) -> ()

export type Modifier = {
	id: string,
	priority: number, -- Lower = applied first (e.g., 10 before 100)
	matches: (ctx: any) -> boolean, -- Should this modifier apply to this query?
	apply: ModifierFunction, -- Transform the result
	source: string?, -- What granted this modifier (equipment, buff, etc.)
}

-- Storage: entityId -> queryType -> array of modifiers
local registry: { [string]: { [string]: { Modifier } } } = {}

-- Register a modifier for an entity and query type
function ModifierRegistry.register(entityId: string, queryType: string, modifier: Modifier)
	if not registry[entityId] then
		registry[entityId] = {}
	end
	if not registry[entityId][queryType] then
		registry[entityId][queryType] = {}
	end

	-- Check if already registered
	local list = registry[entityId][queryType]
	for _, existing in ipairs(list) do
		if existing.id == modifier.id then
			warn(`[ModifierRegistry] Modifier {modifier.id} already registered for {entityId}/{queryType}`)
			return
		end
	end

	table.insert(list, modifier)

	-- Sort by priority (lower = first)
	table.sort(list, function(a, b)
		return a.priority < b.priority
	end)
end

-- Unregister a modifier by ID
function ModifierRegistry.unregister(entityId: string, queryType: string, modifierId: string)
	if not registry[entityId] or not registry[entityId][queryType] then
		return
	end

	local list = registry[entityId][queryType]
	for i, mod in ipairs(list) do
		if mod.id == modifierId then
			table.remove(list, i)
			return
		end
	end
end

-- Unregister all modifiers for an entity (cleanup on death/despawn)
function ModifierRegistry.clearEntity(entityId: string)
	registry[entityId] = nil
end

-- Get all modifiers for an entity and query type
function ModifierRegistry.getModifiers(entityId: string, queryType: string): { Modifier }
	if not registry[entityId] or not registry[entityId][queryType] then
		return {}
	end
	return registry[entityId][queryType]
end

-- Apply all matching modifiers to a query result
function ModifierRegistry.applyModifiers(entityId: string, queryType: string, ctx: any, result: any)
	local modifiers = ModifierRegistry.getModifiers(entityId, queryType)
	if #modifiers == 0 then
		return
	end

	for _, modifier in ipairs(modifiers) do
		if modifier.matches(ctx) then
			modifier.apply(ctx, result)
		end
	end
end

-- Debug: get all modifiers for an entity (all query types)
function ModifierRegistry.getAllModifiers(entityId: string): { [string]: { Modifier } }
	return registry[entityId] or {}
end

return ModifierRegistry
