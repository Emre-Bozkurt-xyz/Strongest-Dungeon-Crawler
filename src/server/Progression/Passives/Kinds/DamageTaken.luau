--!strict
-- kind = "damageTaken": less damage taken, per damage packet.
--   { kind = "damageTaken", reduced = 0.1, when = { damageTypes = { "Fire" } } }
-- `reduced` grows; reductions add up, and never past all of it. The filter reads the attack as the
-- attacker made it (its type, delivery, the attacker's weapon).

local Filters = require(script.Parent.Parent.Filters)
local KindTypes = require(script.Parent.Parent.KindTypes)

local DamageTaken: KindTypes.Kind = {
	kind = "damageTaken",
	incoming = function(ctx, facts, actives)
		for _, packet in ipairs(ctx.packets) do
			if packet.type == "damage" and type(packet.amount) == "number" then
				local reduced = 0
				for _, active in ipairs(actives) do
					if Filters.matchesHit(active.effect.when, facts, packet.damageType or "Physical") then
						reduced += (active.effect.reduced or 0) * active.scale
					end
				end
				if reduced ~= 0 then
					packet.amount *= math.clamp(1 - reduced, 0, 1)
				end
			end
		end
	end,
}

return DamageTaken
