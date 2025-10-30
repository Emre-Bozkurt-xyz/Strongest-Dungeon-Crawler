--!strict
-- Central timing resolver for scaling skill execution based on stats, buffs, and overrides

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = game:GetService("ServerScriptService").Server

local StatTypes = require(ReplicatedStorage.Shared.StatTypes)
local StatsManager = require(Server.Stats.StatsManager)
local SkillsConfig = require(script.Parent.SkillsConfig)

local SkillTimingService = {}

-- Map skill tag -> stat that controls tempo for that tag. Keep lower-case keys.
local TAG_STAT_MAP: { [string]: any } = {
	melee = StatTypes.StaticStats.AttackSpeed :: StatTypes.StaticStatType,
	attack = StatTypes.StaticStats.AttackSpeed :: StatTypes.StaticStatType,
	ranged = StatTypes.StaticStats.AttackSpeed :: StatTypes.StaticStatType,
	physical = StatTypes.StaticStats.AttackSpeed :: StatTypes.StaticStatType,
	spell = StatTypes.StaticStats.SpellCastSpeed :: StatTypes.StaticStatType,
	magic = StatTypes.StaticStats.SpellCastSpeed :: StatTypes.StaticStatType,
	cast = StatTypes.StaticStats.SpellCastSpeed :: StatTypes.StaticStatType,
}

local MIN_TEMPO = 0.05
local MAX_TEMPO = 5

local function resolveStatForSkill(skillConfig: any): StatTypes.StaticStatType?
	if not skillConfig then
		return nil
	end
	local tags = skillConfig.tags or skillConfig.categories
	if type(tags) ~= "table" then
		return nil
	end
	for _, t in ipairs(tags) do
		if type(t) == "string" then
			local key = string.lower(t)
			local mapped = TAG_STAT_MAP[key]
			if mapped ~= nil then
				return mapped :: any
			end
		end
	end
	return nil
end

function SkillTimingService.resolve(entityId: string, skillId: string)
	assert(entityId and skillId and type(skillId) == "string", "SkillTimingService.resolve: bad args")
	local skillConfig = SkillsConfig.skills[skillId]
	local statType = resolveStatForSkill(skillConfig)

	local tempo = 1
	if statType then
		local statValue = StatsManager.getStatValue(entityId, statType :: any)
		if type(statValue) == "number" and statValue > 0 then
			tempo = statValue
		end
	end

	tempo = math.clamp(tempo, MIN_TEMPO, MAX_TEMPO)
	local durationScale = 1 / tempo

	return { durationScale = durationScale, statType = statType }
end

return SkillTimingService
