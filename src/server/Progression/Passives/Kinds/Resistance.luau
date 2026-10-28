--!strict
-- kind = "resistance": resistance to an element from trees.
--   { kind = "resistance", element = "Fire", value = 8 }
-- `value` grows. What all of a character's tree effects give an element is capped low
-- (NodeEffects.TREE_RESISTANCE_CAP, a little more once the element is attuned), so trees never
-- replace gear as the source of resistance -- the content rule, enforced here rather than trusted to
-- the numbers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ModifierFactories = require(ReplicatedStorage.Shared.Modifiers.Factories)
local NodeEffects = require(ReplicatedStorage.Shared.progression.NodeEffects)
local StatsManager = require(ServerScriptService.Server.Stats.StatsManager)
local Filters = require(script.Parent.Parent.Filters)
local KindTypes = require(script.Parent.Parent.KindTypes)

local SOURCE_PREFIX = "passive::resistance::"

local applied: { [string]: { [string]: number } } = {}

local function statOf(element: string): string
	return `{element}Resistance`
end

local function removeAll(entityId: string)
	for element in pairs(applied[entityId] or {}) do
		StatsManager.removeModifier(entityId, statOf(element) :: any, SOURCE_PREFIX .. element)
	end
	applied[entityId] = nil
end

local Resistance: KindTypes.Kind = {
	kind = "resistance",
	apply = function(entityId, actives, loadout)
		if not StatsManager.isRegistered(entityId) then
			applied[entityId] = nil
			return
		end
		local totals: { [string]: number } = {}
		for _, active in ipairs(actives) do
			local effect = active.effect
			if type(effect.element) == "string" and Filters.matchesLoadout(effect.when, loadout) then
				totals[effect.element] = (totals[effect.element] or 0) + (effect.value or 0) * active.scale
			end
		end
		for element, total in pairs(totals) do
			local attuned = loadout.attuned ~= nil and loadout.attuned[element] == true
			local cap = if attuned then NodeEffects.TREE_RESISTANCE_CAP_ATTUNED else NodeEffects.TREE_RESISTANCE_CAP
			totals[element] = math.min(total, cap)
		end
		local previous = applied[entityId] or {}
		for element, value in pairs(previous) do
			if totals[element] ~= value then
				StatsManager.removeModifier(entityId, statOf(element) :: any, SOURCE_PREFIX .. element)
			end
		end
		for element, value in pairs(totals) do
			if previous[element] ~= value then
				local modifier = ModifierFactories.flatAdd({
					sourceId = SOURCE_PREFIX .. element,
					amount = value,
					description = "Passives",
				})
				if not StatsManager.addModifier(entityId, statOf(element) :: any, modifier) then
					totals[element] = nil
				end
			end
		end
		applied[entityId] = totals
	end,
	clear = removeAll,
}

return Resistance
