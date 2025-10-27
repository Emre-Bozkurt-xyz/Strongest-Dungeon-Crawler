--!strict
-- Central timing resolver for scaling skill execution based on stats, buffs, and overrides

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = game:GetService("ServerScriptService").Server

local StatTypes = require(ReplicatedStorage.Shared.StatTypes)
local StatsManager = require(Server.Stats.StatsManager)
local StatsMediator = require(Server.Stats.StatsMediator)
local SkillsConfig = require(script.Parent.SkillsConfig)

type SkillData = SkillsConfig.SkillData
type MediatorQueryOptions = StatsMediator.QueryOptions

export type ResolveContext = {
	step: number?,
	comboStepCount: number?,
	baseDuration: number?,
	timingCategory: string?,
	metadata: { [string]: any }?,
}

export type ResolveResult = {
	category: string,
	statType: StatTypes.StaticStatType?,
	tempo: number,
	durationScale: number,
	metadata: { [string]: any },
}

export type ResolverRequest = {
	entity: Instance,
	skillId: string,
	skillConfig: SkillData?,
	category: string,
	context: ResolveContext?,
}

export type ResolverFn = (ResolverRequest) -> ResolveResult

local SkillTimingService = {}

local CATEGORY_ALIASES = {
	melee = "melee",
	attack = "melee",
	ranged = "melee",
	physical = "melee",
	spell = "spell",
	magic = "spell",
	cast = "spell",
}

local CATEGORY_STAT_MAP: { [string]: StatTypes.StaticStatType? } = {
	default = nil,
	melee = StatTypes.StaticStats.AttackSpeed :: StatTypes.StaticStatType,
	spell = StatTypes.StaticStats.SpellCastSpeed :: StatTypes.StaticStatType,
}

local registeredResolvers: { [string]: ResolverFn } = {}

local MIN_TEMPO = 0.05
local MAX_TEMPO = 5

local function resolveCategory(rawCategory: string?): string
	if not rawCategory or rawCategory == "" then
		return "default"
	end
	local key = string.lower(rawCategory)
	local alias = CATEGORY_ALIASES[key]
	if alias then
		return alias
	end
	return key
end

local function mergeMetadata(base: { [string]: any }?, extra: { [string]: any }?): { [string]: any }
	local merged: { [string]: any } = {}
	if base then
		for key, value in pairs(base) do
			merged[key] = value
		end
	end
	if extra then
		for key, value in pairs(extra) do
			merged[key] = value
		end
	end
	return merged
end

local function applyContextMetadata(
	metadata: { [string]: any },
	skillId: string,
	skillConfig: SkillData?,
	category: string,
	context: ResolveContext?
): { [string]: any }
	local merged = mergeMetadata(context and context.metadata, metadata)
	merged.skill = merged.skill or skillId
	merged.timingCategory = merged.timingCategory or category
	if skillConfig and not merged.skillTags and type((skillConfig :: any).tags) == "table" then
		merged.skillTags = (skillConfig :: any).tags
	end
	if context and context.step then
		merged.step = context.step
	end
	if context and context.comboStepCount then
		merged.comboStepCount = context.comboStepCount
	end
	return merged
end

local function computeTempoFromMetadata(baseTempo: number, metadata: { [string]: any }): number
	local tempo = baseTempo
	local metaTempo = metadata.tempo
	local tempoMultiplier = metadata.tempoMultiplier
	local tempoAdd = metadata.tempoAdd

	if type(tempoMultiplier) == "number" then
		tempo *= tempoMultiplier
	end
	if type(tempoAdd) == "number" then
		tempo += tempoAdd
	end
	if type(metaTempo) == "number" then
		tempo = metaTempo
	end
	return math.clamp(tempo, MIN_TEMPO, MAX_TEMPO)
end

local function defaultResolver(request: ResolverRequest): ResolveResult
	local category = request.category
	local statType: StatTypes.StaticStatType? = CATEGORY_STAT_MAP[category]
	local metadata: { [string]: any } = applyContextMetadata(
		{
			skill = request.skillId,
			category = category,
		},
		request.skillId,
		request.skillConfig,
		category,
		request.context
	)

	local tempo = 1
	local statValue: number? = nil
	if statType then
		local queryOptions: MediatorQueryOptions = {
			context = "resolveSkillTempo",
			event = "resolveSkillTempo",
			originalStat = statType,
			metadata = metadata,
			cacheEnabled = false,
		}
		statValue = StatsManager.getStatValue(request.entity, statType, queryOptions)
		if type(statValue) == "number" and statValue > 0 then
			tempo = statValue
		end
	end

	metadata.statValue = statValue
	tempo = computeTempoFromMetadata(tempo, metadata)
	metadata.finalTempo = tempo

	return {
		category = category,
		statType = statType,
		tempo = tempo,
		durationScale = 1 / tempo,
		metadata = metadata,
	}
end

function SkillTimingService.registerCategory(categoryName: string, resolver: ResolverFn)
	assert(type(categoryName) == "string" and categoryName ~= "", "SkillTimingService.registerCategory requires a category name")
	assert(type(resolver) == "function", "SkillTimingService.registerCategory requires a resolver function")
	registeredResolvers[string.lower(categoryName)] = resolver
end

function SkillTimingService.setCategoryStat(categoryName: string, statType: StatTypes.StaticStatType?)
	assert(type(categoryName) == "string" and categoryName ~= "", "SkillTimingService.setCategoryStat requires a category name")
	CATEGORY_STAT_MAP[string.lower(categoryName)] = statType
end

function SkillTimingService.resolve(entity: Instance, skillId: string, context: ResolveContext?): ResolveResult
	local skillConfig = SkillsConfig.skills[skillId]
	local categoryFromContext = context and context.timingCategory
	local categoryFromConfig = skillConfig and (skillConfig :: any).timingCategory
	local category = resolveCategory(categoryFromContext or categoryFromConfig)

	local resolver = registeredResolvers[category]
	if not resolver then
		resolver = defaultResolver
	end

	return resolver({
		entity = entity,
		skillId = skillId,
		skillConfig = skillConfig,
		category = category,
		context = context,
	})
end

function SkillTimingService.getCategoryStat(categoryName: string): StatTypes.StaticStatType?
	return CATEGORY_STAT_MAP[string.lower(categoryName)]
end

return SkillTimingService
