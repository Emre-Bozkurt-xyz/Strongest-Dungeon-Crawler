--!strict
-- kind = "damage": more damage dealt, per damage packet.
--   { kind = "damage", increased = 0.12, when = { damageTypes = { "Fire" } } }
--   { kind = "damage", perComboStep = 0.1 }  -- each combo step deals more than the last
-- `increased` and `perComboStep` grow. Every matching effect's increase adds up before multiplying,
-- so two +10% passives are +20%, not +21%.

local Filters = require(script.Parent.Parent.Filters)
local KindTypes = require(script.Parent.Parent.KindTypes)

local Damage: KindTypes.Kind = {
	kind = "damage",
	outgoing = function(ctx, facts, actives)
		local stepsIn = math.max(0, (facts.comboStep or 1) - 1)
		for _, packet in ipairs(ctx.packets) do
			if packet.type == "damage" and type(packet.amount) == "number" then
				local increased = 0
				for _, active in ipairs(actives) do
					local effect = active.effect
					if Filters.matchesHit(effect.when, facts, packet.damageType or "Physical") then
						increased += ((effect.increased or 0) + (effect.perComboStep or 0) * stepsIn) * active.scale
					end
				end
				if increased ~= 0 then
					packet.amount = math.max(0, packet.amount * (1 + increased))
				end
			end
		end
	end,
}

return Damage
