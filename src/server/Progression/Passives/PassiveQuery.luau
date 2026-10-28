--!strict
-- Numbers passives decide for skills to read where they shape an attack -- how much larger an
-- explosion is, how much further a swing reaches, how much faster a projectile flies -- kept apart
-- from the passive service so a skill can read them without requiring progression (which requires
-- the skills framework back).
--
-- Each value is an "increased" sum: 0.2 means 20% more. Missing means none.

local PassiveQuery = {}

export type Key = "area" | "reach" | "projectileSpeed"

local values: { [string]: { [string]: number } } = {}

function PassiveQuery.set(entityId: string, key: Key, value: number)
	local entry = values[entityId]
	if not entry then
		entry = {}
		values[entityId] = entry
	end
	if value ~= 0 then
		entry[key] = value
	else
		entry[key] = nil
	end
end

function PassiveQuery.clear(entityId: string)
	values[entityId] = nil
end

-- The multiplier `key` gives `entityId`: 1 when nothing raises it.
function PassiveQuery.multiplier(entityId: string, key: Key): number
	local entry = values[entityId]
	return 1 + (if entry and entry[key] then entry[key] else 0)
end

return PassiveQuery
