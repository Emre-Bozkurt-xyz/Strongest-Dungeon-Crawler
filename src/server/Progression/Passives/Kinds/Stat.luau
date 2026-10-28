--!strict
-- kind = "stat": a stat modifier while the effect holds.
--   { kind = "stat", stat = "AttackSpeed", mode = "percent" | "flat", value = 0.08, when = { contexts } }
-- `value` grows. `percent` is a fraction (0.08 is +8%). Only what is held can limit it (`contexts`,
-- `infusion`); the modifier comes and goes as weapons change.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ModifierFactories = require(ReplicatedStorage.Shared.Modifiers.Factories)
local StatsManager = require(ServerScriptService.Server.Stats.StatsManager)
local Filters = require(script.Parent.Parent.Filters)
local KindTypes = require(script.Parent.Parent.KindTypes)

type Applied = { stat: string, value: number }

local applied: { [string]: { [string]: Applied } } = {}

local function removeAll(entityId: string)
	for sourceId, entry in pairs(applied[entityId] or {}) do
		StatsManager.removeModifier(entityId, entry.stat :: any, sourceId)
	end
	applied[entityId] = nil
end

local Stat: KindTypes.Kind = {
	kind = "stat",
	apply = function(entityId, actives, loadout)
		if not StatsManager.isRegistered(entityId) then
			applied[entityId] = nil
			return
		end
		local previous = applied[entityId] or {}
		local current: { [string]: Applied } = {}
		for _, active in ipairs(actives) do
			local effect = active.effect
			if Filters.matchesLoadout(effect.when, loadout) and type(effect.stat) == "string" then
				current[active.sourceId] = { stat = effect.stat, value = (effect.value or 0) * active.scale }
			end
		end
		for sourceId, entry in pairs(previous) do
			local now = current[sourceId]
			if not now or now.value ~= entry.value then
				StatsManager.removeModifier(entityId, entry.stat :: any, sourceId)
			end
		end
		for sourceId, entry in pairs(current) do
			local before = previous[sourceId]
			if not before or before.value ~= entry.value then
				local effect = nil
				for _, active in ipairs(actives) do
					if active.sourceId == sourceId then
						effect = active.effect
					end
				end
				local modifier = if effect and effect.mode == "percent"
					then ModifierFactories.percentBuff({ sourceId = sourceId, percent = entry.value, description = "Passive" })
					else ModifierFactories.flatAdd({ sourceId = sourceId, amount = entry.value, description = "Passive" })
				if not StatsManager.addModifier(entityId, entry.stat :: any, modifier) then
					current[sourceId] = nil
				end
			end
		end
		applied[entityId] = current
	end,
	clear = removeAll,
}

return Stat
