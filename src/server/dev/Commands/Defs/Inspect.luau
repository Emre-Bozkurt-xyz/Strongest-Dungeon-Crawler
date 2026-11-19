--!strict
-- `inspect`: one entity's live combat state as JSON-safe data -- every stat with its base value,
-- final value and the modifiers between them (and who added each), the status effects on it, and
-- the skill session it is in. The console's Inspect tab shows it; on the command line it prints a
-- summary.

local Support = require(script.Parent.Parent.CommandSupport)

local function round(value: any): any
	if type(value) ~= "number" then
		return value
	end
	if value ~= value or math.abs(value) == math.huge then
		return tostring(value)
	end
	return math.floor(value * 1000 + 0.5) / 1000
end

-- `me` (or nothing) is the calling player; anything else is an NPC name or entity id, nearest first.
local function resolve(context: any, target: string?): (string, Model?)
	local registrar = Support.load("Services.Registrar")
	if target == nil or string.lower(target) == "me" then
		local player, playerId = Support.playerEntity(context)
		return playerId, player.Character
	end
	local matches = Support.livingEntities(target)
	if #matches == 0 then
		-- A dying NPC is still worth looking at, so fall back to any registered entity by id.
		local model = registrar.getEntityById(target)
		if model then
			return target, model
		end
		Support.fail(`no entity named '{target}' (or with that entity id)`)
	end
	local origin = if context.player and context.player.Character then Support.positionOf(context.player.Character) else nil
	local best = matches[1]
	if origin then
		local bestDistance = math.huge
		for _, entity in ipairs(matches) do
			local distance = (Support.positionOf(entity.model) - origin).Magnitude
			if distance < bestDistance then
				best, bestDistance = entity, distance
			end
		end
	end
	return best.id, best.model
end

local function statsOf(entityId: string): { any }
	local stats = Support.load("Stats.StatsManager")
	local all = stats.getAllStats(entityId)
	local out = {}
	if not all then
		return out
	end
	for name, stat in pairs(all) do
		if type(name) ~= "string" or type(stat) ~= "table" or type(stat.getBaseValue) ~= "function" then
			continue
		end
		local entry: { [string]: any } = {
			name = name,
			base = round(stat:getBaseValue()),
			final = round(stats.getStatValue(entityId, name)),
			modifiers = {},
		}
		local current = stats.getPoolCurrentValue(entityId, name)
		if current ~= nil then
			entry.current = round(current)
			entry.max = round(stats.getPoolMaxValue(entityId, name))
		end
		if type(stat.getModifierBreakdown) == "function" then
			local ok, breakdown = pcall(stat.getModifierBreakdown, stat)
			if ok then
				for _, modifier in ipairs(breakdown) do
					table.insert(entry.modifiers, {
						source = tostring(modifier.source),
						name = tostring(modifier.name),
						type = tostring(modifier.type),
						value = round(modifier.value),
					})
				end
			end
		end
		table.insert(out, entry)
	end
	table.sort(out, function(a, b)
		return a.name < b.name
	end)
	return out
end

local function statusesOf(entityId: string): { any }
	local service = Support.load("StatusEffects.StatusEffectsService")
	local now = os.clock()
	local out = {}
	for _, view in ipairs(service.describe(entityId)) do
		table.insert(out, { id = view.id, stacks = view.stacks, remaining = round(math.max(0, view.endsAt - now)) })
	end
	return out
end

local function sessionOf(entityId: string): any?
	local sessions = Support.load("SkillsFramework.SessionManager")
	local snapshot = sessions.getSnapshot(false)
	local entry = snapshot.byCaster[entityId]
	if not entry then
		return nil
	end
	return Support.jsonSafe({
		skillId = entry.skillId,
		state = entry.state,
		stateAge = round(entry.stateAge),
		expiresIn = round(entry.expiresIn),
		recoveryIn = round(entry.recoveryIn),
		combo = entry.combo and {
			currentStep = entry.combo.currentStep,
			totalSteps = entry.combo.totalSteps,
		},
	})
end

return {
	{
		name = "inspect",
		group = "Debug",
		summary = "Show an entity's stats (base, final, modifiers), status effects and skill session: me, or an NPC name or entity id",
		args = {
			{ name = "target", type = "string", default = "me" },
		},
		run = function(context, args)
			local entityId, model = resolve(context, args.target)
			local registrar = Support.load("Services.Registrar")
			local stats = statsOf(entityId)
			local statuses = statusesOf(entityId)
			local session = sessionOf(entityId)
			local name = if model then model.Name else entityId
			local modified = 0
			for _, stat in ipairs(stats) do
				if #stat.modifiers > 0 then
					modified += 1
				end
			end
			local statusNames = {}
			for _, status in ipairs(statuses) do
				table.insert(statusNames, `{status.id} x{status.stacks}`)
			end
			return {
				message = `{name} ({entityId}): {#stats} stats, {modified} modified; statuses: {if #statusNames > 0
					then table.concat(statusNames, ", ")
					else "none"}; session: {if session then `{session.skillId} {session.state}` else "none"}`,
				data = {
					name = name,
					entityId = entityId,
					isPlayer = registrar.isPlayerEntity(entityId),
					stats = stats,
					statuses = statuses,
					session = session,
				},
			}
		end,
	},
}
