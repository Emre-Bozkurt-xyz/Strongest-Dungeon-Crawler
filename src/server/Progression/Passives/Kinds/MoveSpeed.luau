--!strict
-- kind = "moveSpeed": move faster.
--   { kind = "moveSpeed", increased = 0.1 }                                         -- always
--   { kind = "moveSpeed", increased = 0.12, afterUse = { "BasicAttack" }, window = 1.2,
--     when = { contexts = { "sword" } } }                                          -- for a moment after
-- `increased` grows. Through SpeedModifiers, so it combines with slows instead of overwriting them.

local ServerScriptService = game:GetService("ServerScriptService")

local SpeedModifiers = require(ServerScriptService.Server.Movement.SpeedModifiers)
local Filters = require(script.Parent.Parent.Filters)
local KindTypes = require(script.Parent.Parent.KindTypes)
local KindUtil = require(script.Parent.Parent.KindUtil)

local ALWAYS = "passive::moveSpeed"
local BURST = "passive::moveSpeed::burst"

local burstTokens: { [string]: number } = {}

local MoveSpeed: KindTypes.Kind = {
	kind = "moveSpeed",
	apply = function(entityId, actives, loadout)
		local increased = KindUtil.sum(actives, "increased", function(active)
			return active.effect.afterUse == nil and Filters.matchesLoadout(active.effect.when, loadout)
		end)
		if increased ~= 0 then
			SpeedModifiers.set(entityId, ALWAYS, 1 + increased)
		else
			SpeedModifiers.clear(entityId, ALWAYS)
		end
	end,
	onUse = function(entityId, skillName, actives, loadout)
		local increased, window = 0, 0
		for _, active in ipairs(actives) do
			local effect = active.effect
			if
				type(effect.afterUse) == "table"
				and table.find(effect.afterUse, skillName)
				and Filters.matchesLoadout(effect.when, loadout)
			then
				increased += (effect.increased or 0) * active.scale
				window = math.max(window, effect.window or 1)
			end
		end
		if increased == 0 then
			return
		end
		local token = (burstTokens[entityId] or 0) + 1
		burstTokens[entityId] = token
		SpeedModifiers.set(entityId, BURST, 1 + increased)
		task.delay(window, function()
			if burstTokens[entityId] == token then
				burstTokens[entityId] = nil
				SpeedModifiers.clear(entityId, BURST)
			end
		end)
	end,
	clear = function(entityId)
		burstTokens[entityId] = nil
		SpeedModifiers.clear(entityId, ALWAYS)
		SpeedModifiers.clear(entityId, BURST)
	end,
}

return MoveSpeed
