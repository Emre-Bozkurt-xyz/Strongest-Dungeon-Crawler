--!strict
-- kind = "statusBoost": the statuses this character applies are stronger.
--   { kind = "statusBoost", status = "Burn", duration = 0.5 }    -- burns last 50% longer
--   { kind = "statusBoost", status = "Chill", potency = 0.4 }    -- chill slows 40% more
--   { kind = "statusBoost", status = "Burn", extraStacks = 1 }   -- burns stack once more
-- `duration` and `potency` grow; `extraStacks` does not. Applies to every application the
-- character makes -- from passives (StatusParams) and from skills' effect packets alike.

local KindTypes = require(script.Parent.Parent.KindTypes)
local StatusParams = require(script.Parent.Parent.StatusParams)

local StatusBoost: KindTypes.Kind = {
	kind = "statusBoost",
	apply = function(entityId, actives, _loadout)
		local byStatus: { [string]: StatusParams.Boost } = {}
		for _, active in ipairs(actives) do
			local effect = active.effect
			if type(effect.status) == "string" then
				local boost = byStatus[effect.status] or { duration = 0, potency = 0, extraStacks = 0 }
				boost.duration += (effect.duration or 0) * active.scale
				boost.potency += (effect.potency or 0) * active.scale
				boost.extraStacks += effect.extraStacks or 0
				byStatus[effect.status] = boost
			end
		end
		StatusParams.setBoosts(entityId, if next(byStatus) then byStatus else nil)
	end,
	outgoing = function(ctx, facts, _actives)
		for _, packet in ipairs(ctx.packets) do
			if packet.type == "effect" and type(packet.effectId) == "string" then
				packet.params = StatusParams.prepare(facts.sourceId, packet.effectId, packet.params)
			end
		end
	end,
	clear = StatusParams.clear,
}

return StatusBoost
