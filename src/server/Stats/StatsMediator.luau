--!strict
-- StatsMediator: central query and caching layer for stat lookups
-- Phase 1 scaffold: caches per stat type, instrumentation for hits/misses, and query objects

local StatsMediator = {}

local QueryImpl = {}
QueryImpl.__index = QueryImpl

export type StatType = string
export type PlayerStats = { [StatType]: any }
export type QueryOptions = {
	context: string?,
	cacheKey: string?,
	instrument: boolean?,
}

export type CacheEntry = {
	value: number?,
	computedAt: number,
	hitCount: number,
	context: string?,
	lastDurationMs: number?,
}

export type StatCacheBucket = { [string]: CacheEntry }

export type EntityState = {
	stats: PlayerStats,
	cache: { [StatType]: StatCacheBucket },
	hits: number,
	misses: number,
}

type QueryRecord = {
	entity: Instance,
	statType: StatType,
	options: QueryOptions?,
	startedAt: number,
}

export type Query = typeof(setmetatable({} :: QueryRecord, QueryImpl))

local registry: { [Instance]: EntityState } = {}
local globalHits = 0
local globalMisses = 0

local function ensureState(entity: Instance): EntityState?
	return registry[entity]
end

local function captureDuration(startedAt: number?): number?
	if not startedAt then
		return nil
	end
	return (os.clock() - startedAt) * 1000
end

local function resolveQuery(self: Query, computeFn: () -> number?): number?
	local entity = self.entity
	local statType = self.statType
	local options = self.options

	local state = ensureState(entity)
	if not state then
		return computeFn()
	end

	local cacheKey = if options and options.cacheKey then options.cacheKey else "value"
	local bucket = state.cache[statType]
	if not bucket then
		bucket = {}
		state.cache[statType] = bucket
	end

	local entry = bucket[cacheKey]
	if entry then
		entry.hitCount += 1
		state.hits += 1
		globalHits += 1
		return entry.value
	end

	local startedAt = if options and options.instrument then os.clock() else nil
	local value = computeFn()

	local durationMs = captureDuration(startedAt)
	bucket[cacheKey] = {
		value = value,
		computedAt = os.clock(),
		hitCount = 0,
		context = options and options.context or nil,
		lastDurationMs = durationMs,
	}

	state.misses += 1
	globalMisses += 1

	return value
end

function QueryImpl:resolve(computeFn: () -> number?)
	return resolveQuery(self, computeFn)
end

function StatsMediator.beginQuery(entity: Instance, statType: StatType, options: QueryOptions?): Query
	return setmetatable({
		entity = entity,
		statType = statType,
		options = options,
		startedAt = os.clock(),
	}, QueryImpl)
end

function StatsMediator.resolve(entity: Instance, statType: StatType, computeFn: () -> number?, options: QueryOptions?): number?
	local query = StatsMediator.beginQuery(entity, statType, options)
	return query:resolve(computeFn)
end

function StatsMediator.attach(entity: Instance, stats: PlayerStats)
	local state = registry[entity]
	if state then
		state.stats = stats
		state.cache = state.cache or {}
		return
	end
	registry[entity] = {
		stats = stats,
		cache = {},
		hits = 0,
		misses = 0,
	}
end

function StatsMediator.detach(entity: Instance)
	registry[entity] = nil
end

function StatsMediator.invalidate(entity: Instance, statType: StatType?, cacheKey: string?)
	local state = registry[entity]
	if not state then
		return
	end
	if not statType then
		for key in pairs(state.cache) do
			state.cache[key] = nil
		end
		return
	end
	local bucket = state.cache[statType]
	if not bucket then
		return
	end
	if cacheKey then
		bucket[cacheKey] = nil
		return
	end
	state.cache[statType] = nil
end

function StatsMediator.invalidateAll(entity: Instance)
	StatsMediator.invalidate(entity, nil, nil)
end

function StatsMediator.invalidateStat(entity: Instance, statType: StatType)
	StatsMediator.invalidate(entity, statType, nil)
end

function StatsMediator.getState(entity: Instance): EntityState?
	return registry[entity]
end

function StatsMediator.getDebugSnapshot(entity: Instance?): any
	if entity ~= nil then
		local state = registry[entity]
		if not state then
			return nil
		end
		return {
			hits = state.hits,
			misses = state.misses,
			cache = state.cache,
		}
	end

	return {
		totalHits = globalHits,
		totalMisses = globalMisses,
	}
end

return StatsMediator
