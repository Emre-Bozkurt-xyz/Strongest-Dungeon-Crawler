--!strict
-- Commands that run through the real combat and status paths against NPCs, so kills, statuses and
-- what follows them can be exercised without a build that causes them.

local Support = require(script.Parent.Parent.CommandSupport)

local function effectIds(): { string }
	local ids: { string } = {}
	for key, def in pairs(Support.load("StatusEffects.EffectsIndex")) do
		if type(key) == "string" and type(def) == "table" then
			table.insert(ids, key)
		end
	end
	table.sort(ids)
	return ids
end

return {
	{
		name = "hit",
		group = "Combat",
		summary = "Land a plain physical hit from you on the nearest living NPC with that name (or that entity id)",
		args = {
			{ name = "npc", type = "string" },
			{ name = "amount", type = "number", min = 0 },
		},
		run = function(context, args)
			local player, playerId = Support.playerEntity(context)
			local origin = Support.characterPosition(player)
			local npcName: string = args.npc

			local nearest: Support.LivingEntity? = nil
			local nearestDistance = math.huge
			for _, entity in ipairs(Support.livingEntities(npcName)) do
				local distance = (Support.positionOf(entity.model) - origin).Magnitude
				if distance < nearestDistance then
					nearest, nearestDistance = entity, distance
				end
			end
			if not nearest then
				Support.fail(`no living NPC named '{npcName}'`)
			end

			Support.load("Services.CombatService").applyAttack(nearest.id, {
				packets = { { type = "damage", damageType = "Physical", amount = args.amount } },
				sourceId = playerId,
				metadata = { skillId = "DevHit" },
			}, playerId)
			return `hit {nearest.model.Name} for {args.amount}`
		end,
	},
	{
		name = "status",
		group = "Combat",
		summary = "Put a status effect from you on every living NPC with that name (or the one with that entity id)",
		args = {
			{ name = "npc", type = "string" },
			{ name = "effect", type = "choice", choices = effectIds },
			{ name = "params", type = "json", optional = true },
		},
		run = function(context, args)
			local _, playerId = Support.playerEntity(context)
			local npcName: string = args.npc
			local targets = Support.livingEntities(npcName)
			if #targets == 0 then
				Support.fail(`no living NPC named '{npcName}'`)
			end
			local statusEffects = Support.load("StatusEffects.StatusEffectsService")
			for _, target in ipairs(targets) do
				statusEffects.apply(target.id, args.effect, playerId, args.params)
			end
			return `applied {args.effect} to {#targets} NPC(s) named {npcName}`
		end,
	},
}
