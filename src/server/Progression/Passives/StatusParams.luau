--!strict
-- The parameters a status is applied with, once its source's passives have had their say: a status
-- definition's defaults, then the source's boosts to that status ("burns last longer", "chill is
-- stronger", "burns stack once more").
--
-- A definition names which of its parameters are its strength (`potencyKeys`, e.g. Burn's
-- `damagePerTick`), so a potency boost needs no list of its own per status.

local ServerScriptService = game:GetService("ServerScriptService")

local StatusEffectsService = require(ServerScriptService.Server.StatusEffects.StatusEffectsService)

export type Boost = {
	-- Increased duration, potency (both fractions) and extra stacks, summed over every boost.
	duration: number,
	potency: number,
	extraStacks: number,
}

local StatusParams = {}

local boosts: { [string]: { [string]: Boost } } = {}

function StatusParams.setBoosts(entityId: string, byStatus: { [string]: Boost }?)
	if byStatus then
		boosts[entityId] = byStatus
	else
		boosts[entityId] = nil
	end
end

-- `params` as `sourceId` applies status `statusId`: defaults filled in, boosts applied. A new table;
-- `params` is not changed.
function StatusParams.prepare(sourceId: string?, statusId: string, params: { [string]: any }?): { [string]: any }
	local def = StatusEffectsService.getDef(statusId)
	local out: { [string]: any } = {}
	if def and type(def.defaultParams) == "table" then
		for key, value in pairs(def.defaultParams) do
			out[key] = value
		end
	end
	for key, value in pairs(params or {}) do
		out[key] = value
	end
	local boost = sourceId and boosts[sourceId] and boosts[sourceId][statusId]
	if not boost then
		return out
	end
	if boost.duration ~= 0 then
		local base = out.duration or (def and def.duration) or 0
		out.duration = base * (1 + boost.duration)
	end
	if boost.potency ~= 0 and def and type(def.potencyKeys) == "table" then
		for _, key in ipairs(def.potencyKeys) do
			if type(out[key]) == "number" then
				out[key] *= 1 + boost.potency
			end
		end
	end
	if boost.extraStacks > 0 then
		out.maxStacks = ((def and def.maxStacks) or 1) + boost.extraStacks
	end
	return out
end

function StatusParams.clear(entityId: string)
	boosts[entityId] = nil
end

return StatusParams
