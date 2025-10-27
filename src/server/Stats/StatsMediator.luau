--!strict
-- StatsMediator: central query and caching layer for stat lookups with observer hooks

local StatsMediator = {}

local QueryImpl = {}
QueryImpl.__index = QueryImpl

export type StatType = string
export type PlayerStats = { [StatType]: any }

export type QueryOptions = {
	context: string?,
	cacheKey: string?,
	event: string?,
	metadata: { [string]: any }?,
	instrument: boolean?,
	allowObservers: boolean?,
	cacheEnabled: boolean?,
	originalStat: StatType?,
	overrideStat: StatType?,
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

export type ObserverContext = {
	event: string,
	entity: Instance,
	statType: StatType,
	originalStatType: StatType?,
	options: QueryOptions?,
	compute: () -> number?,
}

export type ObserverResult = {
	handled: boolean?,
	value: number?,
	cacheKey: string?,
	storeInCache: boolean?,
}

type ObserverCallback = (ObserverContext) -> ObserverResult?

type QueryRecord = {
	entity: Instance,
	statType: StatType,
	options: QueryOptions?,
	startedAt: number,
}

export type Query = typeof(setmetatable({} :: QueryRecord, QueryImpl))

local registry: { [Instance]: EntityState } = {}
local observers: { [string]: { [string]: ObserverCallback } } = {}
local observerSeq = 0

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

local function emit(eventName: string, context: ObserverContext): ObserverResult?
	local bucket = observers[eventName]
	if not bucket then
		return nil
	end
	for _, callback in pairs(bucket) do
		local ok, result = pcall(callback, context)
		if not ok then
			warn(string.format("[StatsMediator] Observer '%s' errored: %s", eventName, tostring(result)))
		elseif result ~= nil then
			if result.handled == nil or result.handled == true then
				return result
			end
		end
	end
	return nil
end

local function resolveQuery(self: Query, computeFn: () -> number?): number?
	local entity = self.entity
	local statType = self.statType
	local options = self.options

	local state = ensureState(entity)
	local cacheEnabled = not (options and options.cacheEnabled == false)

	local cacheKey = if options and options.cacheKey then options.cacheKey else "value"
	local bucket: StatCacheBucket? = nil
	if state and cacheEnabled then
		local existingBucket = state.cache[statType]
		if not existingBucket then
			existingBucket = {}
			state.cache[statType] = existingBucket
		end
		bucket = existingBucket
		local entry = existingBucket[cacheKey]
		if entry then
			entry.hitCount += 1
			state.hits += 1
			globalHits += 1
			return entry.value
		end
	end

	local instrument = options and options.instrument
	local startedAt: number? = nil
	local durationMs: number? = nil
	local computed = false
	local computedValue: number? = nil

	local function computeWithInstrumentation(): number?
		if computed then
			return computedValue
		end
		if instrument then
			startedAt = os.clock()
		end
		computedValue = computeFn()
		computed = true
		if instrument then
			durationMs = captureDuration(startedAt)
		end
		return computedValue
	end

	local value: number?
	local eventName = if options then options.event or options.context else nil
	local allowObservers = (options == nil) or (options.allowObservers ~= false)

	if allowObservers and eventName then
		local observerResult = emit(eventName, {
			event = eventName,
			entity = entity,
			statType = statType,
			originalStatType = options and options.originalStat or statType,
			options = options,
			compute = computeWithInstrumentation,
		})
		if observerResult then
			value = observerResult.value
			cacheKey = observerResult.cacheKey or cacheKey
			local shouldStore = observerResult.storeInCache ~= false
			if state then
				state.misses += 1
				globalMisses += 1
			end
			if state and cacheEnabled and shouldStore then
				local targetBucket = bucket
				if not targetBucket then
					targetBucket = {}
					state.cache[statType] = targetBucket
				end
				local bucketToUse = targetBucket :: StatCacheBucket
				bucketToUse[cacheKey] = {
					value = value,
					computedAt = os.clock(),
					hitCount = 0,
					context = options and options.context or nil,
					lastDurationMs = durationMs,
				}
			end
			return value
		end
	end

	value = computeWithInstrumentation()
	if state then
		state.misses += 1
		globalMisses += 1
	end

	if state and cacheEnabled then
		local targetBucket = bucket or state.cache[statType]
		if not targetBucket then
			targetBucket = {}
			state.cache[statType] = targetBucket
		end
		local bucketToUse = targetBucket :: StatCacheBucket
		bucketToUse[cacheKey] = {
			value = value,
			computedAt = os.clock(),
			hitCount = 0,
			context = options and options.context or nil,
			lastDurationMs = durationMs,
		}
	end

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

function StatsMediator.observe(eventName: string, callback: ObserverCallback): string
	assert(eventName ~= nil and eventName ~= "", "StatsMediator.observe requires an event name")
	observerSeq += 1
	local token = string.format("%s#%d", eventName, observerSeq)
	local bucket = observers[eventName]
	if not bucket then
		bucket = {}
		observers[eventName] = bucket
	end
	bucket[token] = callback
	return token
end

function StatsMediator.forget(eventName: string, token: string): boolean
	local bucket = observers[eventName]
	if not bucket then
		return false
	end
	if bucket[token] then
		bucket[token] = nil
		if next(bucket) == nil then
			observers[eventName] = nil
		end
		return true
	end
	return false
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
