--!strict
-- kind = "critChance": crit chance for matching hits, in percentage points.
--   { kind = "critChance", value = 5, when = { contexts = { "bow" } } }
-- kind = "critDamage": a larger crit multiplier for matching hits.
--   { kind = "critDamage", increased = 0.3, when = { targetHas = "Chill" } }
-- `value` and `increased` grow. Both set the packet's own bonus (CombatService), so they only touch
-- the hits they name rather than the character's crit stats.

local Filters = require(script.Parent.Parent.Filters)
local KindTypes = require(script.Parent.Parent.KindTypes)
local KindUtil = require(script.Parent.Parent.KindUtil)

local function perPacket(field: string, packetField: string): (any, any, { KindTypes.Active }) -> ()
	return function(ctx, facts, actives)
		for _, packet in ipairs(ctx.packets) do
			if packet.type == "damage" then
				local bonus = KindUtil.sum(actives, field, function(active)
					return Filters.matchesHit(active.effect.when, facts, packet.damageType or "Physical")
				end)
				if bonus ~= 0 then
					local current = (packet :: any)[packetField]
					;(packet :: any)[packetField] = (if type(current) == "number" then current else 0) + bonus
				end
			end
		end
	end
end

local CritChance: KindTypes.Kind = {
	kind = "critChance",
	outgoing = perPacket("value", "critChanceBonus"),
}

local CritDamage: KindTypes.Kind = {
	kind = "critDamage",
	outgoing = perPacket("increased", "critDamageBonus"),
}

return { CritChance, CritDamage }
