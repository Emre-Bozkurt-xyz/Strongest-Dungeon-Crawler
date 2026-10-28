--!strict
-- Effects on an attack's shape, read by the skills that make it (PassiveQuery):
--   { kind = "area", increased = 0.2 }                                  -- larger explosions and rings
--   { kind = "reach", increased = 0.2, when = { infusion = "Fire" } }   -- swings and shots reach further
--   { kind = "projectileSpeed", increased = 0.2, when = { contexts = { "bow" } } }
-- `increased` grows. Only what is held can limit them (`contexts`, `infusion`).

local Filters = require(script.Parent.Parent.Filters)
local KindTypes = require(script.Parent.Parent.KindTypes)
local KindUtil = require(script.Parent.Parent.KindUtil)
local PassiveQuery = require(script.Parent.Parent.PassiveQuery)

local function queryKind(key: PassiveQuery.Key): KindTypes.Kind
	return {
		kind = key,
		apply = function(entityId, actives, loadout)
			PassiveQuery.set(
				entityId,
				key,
				KindUtil.sum(actives, "increased", function(active)
					return Filters.matchesLoadout(active.effect.when, loadout)
				end)
			)
		end,
		clear = PassiveQuery.clear,
	}
end

return { queryKind("area"), queryKind("reach"), queryKind("projectileSpeed") }
