--!strict
-- kind = "onKill": something happens where an enemy the character killed falls.
--   { kind = "onKill", action = "explode", element = "Fire", maxHealthShare = 0.1, radius = 8,
--     status = "Chill", when = { targetHas = "Burn" } }
--     -- every other enemy within `radius` takes `maxHealthShare` of the dead enemy's max health as
--     -- `element` damage, and `status` if given
--   { kind = "onKill", action = "spread", status = "Burn", radius = 12, count = 1,
--     when = { targetHas = "Burn" } }
--     -- the dead enemy's `status` passes to the `count` nearest enemies within `radius`
-- `maxHealthShare` grows. `when` is checked against the enemy as it died (its statuses still on it).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local StatTypes = require(ReplicatedStorage.Shared.StatTypes)

local Server = ServerScriptService.Server
local CombatService = require(Server.Services.CombatService)
local StatsManager = require(Server.Stats.StatsManager)
local StatusEffectsService = require(Server.StatusEffects.StatusEffectsService)
local HitboxService = require(Server.SkillsFramework.HitboxService)
local Registrar = require(Server.Services.Registrar)
local Filters = require(script.Parent.Parent.Filters)
local KindTypes = require(script.Parent.Parent.KindTypes)
local StatusParams = require(script.Parent.Parent.StatusParams)

local function enemiesAround(killerId: string, position: Vector3, radius: number, except: string): { string }
	local found = HitboxService.newQuery(CFrame.new(position))
		:casterEntityId(killerId)
		:factionRelation("enemy")
		:playersOnly(false)
		:sphere(radius)
		:collect({ collectIds = true })
	local out: { string } = {}
	for _, id in ipairs(found.ids or {}) do
		if id ~= except then
			table.insert(out, id)
		end
	end
	return out
end

local function explode(kill: KindTypes.KillFacts, active: KindTypes.Active)
	local effect = active.effect
	local maxHealth = StatsManager.getPoolMaxValue(kill.targetId, StatTypes.PoolStats.Health) or 0
	local amount = maxHealth * (effect.maxHealthShare or 0) * active.scale
	local packets: { any } = {}
	if amount > 0 then
		table.insert(packets, { type = "damage", damageType = effect.element or "Physical", amount = amount })
	end
	if type(effect.status) == "string" then
		table.insert(packets, {
			type = "effect",
			effectId = effect.status,
			params = StatusParams.prepare(kill.killerId, effect.status, nil),
		})
	end
	if #packets == 0 then
		return
	end
	for _, id in ipairs(enemiesAround(kill.killerId, kill.position, effect.radius or 8, kill.targetId)) do
		CombatService.applyAttack(id, {
			packets = packets,
			sourceId = kill.killerId,
			-- An effect of a kill, not a skill: it teaches no mastery, cannot crit, and is not an "area"
			-- hit, so it cannot set off area passives and chain.
			metadata = { skillId = "Passive", delivery = "burst", isCrit = false },
		}, kill.killerId)
	end
end

local function positionOf(id: string): Vector3?
	local model = Registrar.getEntityById(id)
	local root = model and model:FindFirstChild("HumanoidRootPart") :: BasePart?
	return if root then root.Position else nil
end

local function spread(kill: KindTypes.KillFacts, active: KindTypes.Active)
	local effect = active.effect
	local status = effect.status
	if type(status) ~= "string" then
		return
	end
	local params = StatusEffectsService.getParams(kill.targetId, status)
	if params == nil then
		return
	end
	local nearby = enemiesAround(kill.killerId, kill.position, effect.radius or 12, kill.targetId)
	table.sort(nearby, function(a, b)
		local pa, pb = positionOf(a), positionOf(b)
		local da = if pa then (pa - kill.position).Magnitude else math.huge
		local db = if pb then (pb - kill.position).Magnitude else math.huge
		return da < db
	end)
	for i = 1, math.min(effect.count or 1, #nearby) do
		StatusEffectsService.apply(nearby[i], status, kill.killerId, table.clone(params))
	end
end

local OnKill: KindTypes.Kind = {
	kind = "onKill",
	onKill = function(kill, actives)
		local facts: Filters.HitFacts = {
			context = "",
			sourceId = kill.killerId,
			targetId = kill.targetId,
			finalStep = false,
		}
		for _, active in ipairs(actives) do
			local filter = active.effect.when
			if filter and (filter.targetHas or filter.targetStacks) then
				-- Only the dead enemy's statuses are known at a kill; the rest of a filter is about hits.
				local onTarget = { targetHas = filter.targetHas, targetStacks = filter.targetStacks }
				if not Filters.matchesHit(onTarget :: any, facts, nil) then
					continue
				end
			end
			if active.effect.action == "explode" then
				explode(kill, active)
			elseif active.effect.action == "spread" then
				spread(kill, active)
			end
		end
	end,
}

return OnKill
