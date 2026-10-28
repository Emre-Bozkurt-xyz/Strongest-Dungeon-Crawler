--!strict
-- How hard hits move and stagger, dealt and taken.
--   { kind = "knockback", dealt = 0.3 }   -- knocks back further
--   { kind = "knockback", taken = -0.4 }  -- knocked back less
--   { kind = "stagger", dealt = 0.4 }     -- staggers more
-- `dealt` and `taken` grow. The attacker's `dealt` and the target's `taken` both apply to a hit.

local Filters = require(script.Parent.Parent.Filters)
local KindTypes = require(script.Parent.Parent.KindTypes)
local KindUtil = require(script.Parent.Parent.KindUtil)

local function total(actives: { KindTypes.Active }, field: string, facts: any): number
	return KindUtil.sum(actives, field, function(active)
		return Filters.matchesHit(active.effect.when, facts, nil)
	end)
end

local function scaleKnockback(ctx: any, change: number)
	if change == 0 then
		return
	end
	for _, packet in ipairs(ctx.packets) do
		if packet.type == "knockback" and type(packet.distance) == "number" then
			packet.distance = math.max(0, packet.distance * (1 + change))
		end
	end
end

local function scaleStagger(ctx: any, change: number)
	if change == 0 then
		return
	end
	local current = ctx.metadata.staggerScale
	ctx.metadata.staggerScale = math.max(0, (if type(current) == "number" then current else 1) * (1 + change))
end

local Knockback: KindTypes.Kind = {
	kind = "knockback",
	outgoing = function(ctx, facts, actives)
		scaleKnockback(ctx, total(actives, "dealt", facts))
	end,
	incoming = function(ctx, facts, actives)
		scaleKnockback(ctx, total(actives, "taken", facts))
	end,
}

local Stagger: KindTypes.Kind = {
	kind = "stagger",
	outgoing = function(ctx, facts, actives)
		scaleStagger(ctx, total(actives, "dealt", facts))
	end,
	incoming = function(ctx, facts, actives)
		scaleStagger(ctx, total(actives, "taken", facts))
	end,
}

return { Knockback, Stagger }
