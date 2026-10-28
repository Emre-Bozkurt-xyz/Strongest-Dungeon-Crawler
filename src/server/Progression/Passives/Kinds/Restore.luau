--!strict
-- kind = "restore": a matching hit gives some of a resource back.
--   { kind = "restore", resource = "Stamina", amount = 12, when = { comboStep = "final" } }
-- `amount` grows. Once per moment, not once per target: one swing that lands on three enemies is
-- one landed combo.

local ServerScriptService = game:GetService("ServerScriptService")

local StatsManager = require(ServerScriptService.Server.Stats.StatsManager)
local Filters = require(script.Parent.Parent.Filters)
local KindTypes = require(script.Parent.Parent.KindTypes)
local KindUtil = require(script.Parent.Parent.KindUtil)

local ONCE_PER = 0.3

local ready = KindUtil.cooldown()

local Restore: KindTypes.Kind = {
	kind = "restore",
	afterHit = function(facts, actives)
		for _, active in ipairs(actives) do
			local effect = active.effect
			if
				type(effect.resource) == "string"
				and Filters.matchesHit(effect.when, facts, nil)
				and ready(active.sourceId .. "|" .. facts.sourceId, ONCE_PER)
			then
				StatsManager.addToPool(facts.sourceId, effect.resource :: any, (effect.amount or 0) * active.scale)
			end
		end
	end,
}

return Restore
