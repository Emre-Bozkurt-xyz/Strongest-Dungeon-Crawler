--!strict
-- kind = "onHit": apply a status to what a matching hit struck.
--   { kind = "onHit", status = "Burn", chance = 0.25, fromDamage = { damagePerTick = 0.12 },
--     params = { duration = 3 }, cooldown = 4, when = { damageTypes = { "Fire" } } }
-- `fromDamage` sets a parameter from what the hit dealt: the share given, of the damage of the
-- filter's `damageTypes` (all of it without), growing with the node. `params` are fixed. `cooldown`
-- (seconds) limits it per target, for effects that would otherwise never let go (Freeze). The
-- source's boosts to the status (statusBoost) apply on top.

local ServerScriptService = game:GetService("ServerScriptService")

local StatusEffectsService = require(ServerScriptService.Server.StatusEffects.StatusEffectsService)
local Filters = require(script.Parent.Parent.Filters)
local KindTypes = require(script.Parent.Parent.KindTypes)
local KindUtil = require(script.Parent.Parent.KindUtil)
local StatusParams = require(script.Parent.Parent.StatusParams)

local ready = KindUtil.cooldown()

local function damageOf(types: { string }?, byType: { [string]: number }?): number
	local total = 0
	for damageType, amount in pairs(byType or {}) do
		if types == nil or table.find(types, damageType) then
			total += amount
		end
	end
	return total
end

local OnHit: KindTypes.Kind = {
	kind = "onHit",
	afterHit = function(facts, actives)
		for _, active in ipairs(actives) do
			local effect = active.effect
			if type(effect.status) ~= "string" or not Filters.matchesHit(effect.when, facts, nil) then
				continue
			end
			local chance = if type(effect.chance) == "number" then effect.chance else 1
			if math.random() >= chance then
				continue
			end
			if
				type(effect.cooldown) == "number"
				and not ready(`{active.sourceId}|{facts.targetId}`, effect.cooldown)
			then
				continue
			end
			local params: { [string]: any } = table.clone(effect.params or {})
			if type(effect.fromDamage) == "table" then
				local dealt = damageOf(effect.when and effect.when.damageTypes, facts.byType)
				for key, share in pairs(effect.fromDamage) do
					params[key] = dealt * share * active.scale
				end
			end
			StatusEffectsService.apply(
				facts.targetId,
				effect.status,
				facts.sourceId,
				StatusParams.prepare(facts.sourceId, effect.status, params)
			)
		end
	end,
}

return OnHit
