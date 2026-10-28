--!strict
-- kind = "cost": what skills cost in one resource.
--   { kind = "cost", resource = "Mana", reduced = 0.15 }
--   { kind = "cost", resource = "Mana", increased = 0.5, when = { comboStep = "final" } }
-- `reduced` and `increased` grow. Applied as a skill cost modifier (SkillModifierRegistry), so the
-- server's charge and the cost preview the client predicts from (SkillMetadataService) both see it.

local ServerScriptService = game:GetService("ServerScriptService")

local SkillModifierRegistry = require(ServerScriptService.Server.Stats.SkillModifierRegistry)
local Filters = require(script.Parent.Parent.Filters)
local Facts = require(script.Parent.Parent.Facts)
local KindTypes = require(script.Parent.Parent.KindTypes)

local EVENT = "resolveSkillCost"

-- Registered modifier ids and the multiplier each applied, per entity.
local registered: { [string]: { [string]: number } } = {}

local function removeAll(entityId: string)
	for id in pairs(registered[entityId] or {}) do
		SkillModifierRegistry.unregister(entityId, EVENT, id)
	end
	registered[entityId] = nil
end

local function register(entityId: string, active: KindTypes.Active, multiplier: number)
	local effect = active.effect
	SkillModifierRegistry.register(entityId, EVENT, {
		id = active.sourceId,
		priority = 50,
		matches = function(ctx)
			local base = ctx.base
			if not base or base.resource ~= effect.resource then
				return false
			end
			local filter = effect.when
			if not filter then
				return true
			end
			local skillId = ctx.skillId
			local step = if type(ctx.step) == "number" then ctx.step else nil
			local loadout = Facts.loadoutOf(entityId)
			local track, final = Facts.attackOf(entityId, skillId, step)
			return Filters.matchesHit(filter, {
				context = loadout.context,
				infusion = loadout.infusion,
				sourceId = entityId,
				targetId = "",
				skillId = skillId,
				comboStep = step,
				finalStep = final,
				track = track,
			}, nil)
		end,
		apply = function(_ctx, result)
			local values = result.values
			if values and type(values.amount) == "number" then
				values.amount = math.max(0, values.amount * multiplier)
			end
		end,
	})
end

local Cost: KindTypes.Kind = {
	kind = "cost",
	apply = function(entityId, actives, _loadout)
		local previous = registered[entityId] or {}
		local current: { [string]: number } = {}
		for _, active in ipairs(actives) do
			local effect = active.effect
			current[active.sourceId] = 1 - (effect.reduced or 0) * active.scale + (effect.increased or 0) * active.scale
		end
		for id, multiplier in pairs(previous) do
			if current[id] ~= multiplier then
				SkillModifierRegistry.unregister(entityId, EVENT, id)
			end
		end
		for _, active in ipairs(actives) do
			local multiplier = current[active.sourceId]
			if previous[active.sourceId] ~= multiplier then
				register(entityId, active, multiplier)
			end
		end
		registered[entityId] = current
	end,
	clear = removeAll,
}

return Cost
