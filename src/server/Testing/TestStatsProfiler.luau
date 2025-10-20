--!strict
-- Ad-hoc micro-benchmark suite for the stats/attributes pipeline.
-- Usage (in Studio command bar or a server script):
--   local profiler = require(game.ServerScriptService.Server.Testing.TestStatsProfiler)
--   profiler.run({ iterations = 50000 })

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = game:GetService("ServerScriptService").Server

local StatsConfig = require(Server.Stats.Config.StatsConfig)
local StatsManager = require(Server.Stats.StatsManager)
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)
local StatModifier = require(ReplicatedStorage.Shared.Modifiers.StatModifier)
local PercentOfStatModifier = require(ReplicatedStorage.Shared.Modifiers.PercentOfStatModifier)

export type BenchmarkResult = {
	label: string,
	iterations: number,
	totalMs: number,
	perUs: number,
}

export type RunOptions = {
	iterations: number?,
	modifierIterations: number?,
}

local TestStatsProfiler = {}

local function formatResult(label: string, iterations: number, duration: number): BenchmarkResult
	local totalMs = duration * 1000
	local perUs = (iterations > 0) and ((duration / iterations) * 1e6) or 0
	print(string.format("[StatsProfiler] %s -> %.3f ms total (%.2f µs/op)", label, totalMs, perUs))
	return {
		label = label,
		iterations = iterations,
		totalMs = totalMs,
		perUs = perUs,
	}
end

local function timeIt(label: string, iterations: number, callback: (number) -> ())
	local start = os.clock()
	for i = 1, iterations do
		callback(i)
	end
	local duration = os.clock() - start
	return formatResult(label, iterations, duration)
end

local function buildStatWithModifiers(modCount: number)
	local stats = StatsConfig.createDefaultStats()
	local stat = stats[StatTypes.StaticStats.PhysicalDamage]
	for i = 1, modCount do
		stat:addModifier(StatModifier.new({
			value = 5,
			type = "flat",
			source_id = string.format("bench_flat_%03d", i),
		}))
	end
	return stats, stat
end

local function benchmarkStatGetValue(modCount: number, iterations: number, invalidate: boolean)
	local stats, stat = buildStatWithModifiers(modCount)
	local labelSuffix = invalidate and "recompute" or "cached"

	if not invalidate then
		stat:invalidateCache()
		stat:getValue(stats)
	end

	return timeIt(string.format("PhysicalDamage:getValue (mods=%d, %s)", modCount, labelSuffix), iterations, function()
		if invalidate then
			stat:invalidateCache()
		end
		stat:getValue(stats)
	end)
end

local function benchmarkModifierMutation(baseModifiers: number, iterations: number)
	local _stats, stat = buildStatWithModifiers(baseModifiers)

	return timeIt(string.format("Stat:add/remove modifier (base=%d)", baseModifiers), iterations, function(i)
		local sourceId = string.format("bench_mut_%06d", i)
		local modifier = StatModifier.new({
			value = 2,
			type = "flat",
			source_id = sourceId,
		})
		stat:addModifier(modifier)
		stat:removeModifier(sourceId)
	end)
end

local function benchmarkPoolOperations(iterations: number)
	local stats = StatsConfig.createDefaultStats()
	local pool = stats[StatTypes.PoolStats.Stamina]

	return timeIt("Stamina add/remove (±5)", iterations, function()
		pool:addToCurrentValue(5, stats)
		pool:removeFromCurrentValue(5, stats)
	end)
end

local function benchmarkPercentModifier(iterations: number)
	local stats = StatsConfig.createDefaultStats()
	local sourceStat = stats[StatTypes.StaticStats.PhysicalDamage]
	sourceStat:setBaseValue(120)
	local targetStat = stats[StatTypes.StaticStats.MagicDamage]
	local modifier = PercentOfStatModifier.new({
		value = 0.25,
		source_id = "bench_percent",
		description = "Bench Percent",
		targetStat = StatTypes.StaticStats.PhysicalDamage,
	})
	targetStat:addModifier(modifier)

	return timeIt("PercentOfStatModifier recompute", iterations, function()
		targetStat:invalidateCache()
		targetStat:getValue(stats)
	end)
end

local function benchmarkInvalidateAllCaches(modCount: number, iterations: number)
	local dummy = Instance.new("Folder")
	dummy.Name = "StatsProfilerDummy"
	local stats, _stat = buildStatWithModifiers(modCount)
	StatsManager.register(dummy, {
		stats = stats,
		skipSync = true,
	})

	local result = timeIt(string.format("StatsManager.invalidateAllCaches (mods=%d)", modCount), iterations, function()
		StatsManager.invalidateAllCaches(dummy)
	end)

	StatsManager.unregister(dummy)
	dummy:Destroy()

	-- restore caches once for cleanliness
	for _, s in pairs(stats) do
		if s.invalidateCache then
			s:invalidateCache()
		end
	end

	return result
end

function TestStatsProfiler.run(options: RunOptions?)
	local iterations = (options and options.iterations) or 50000
	local modifierIterations = (options and options.modifierIterations) or 10000

	print("\n=== Stats Profiler ===")
	local results: { BenchmarkResult } = {}

	table.insert(results, benchmarkStatGetValue(0, iterations, true))
	table.insert(results, benchmarkStatGetValue(5, iterations, true))
	table.insert(results, benchmarkStatGetValue(20, iterations, true))
	table.insert(results, benchmarkStatGetValue(20, iterations, false))

	table.insert(results, benchmarkModifierMutation(5, modifierIterations))
	table.insert(results, benchmarkModifierMutation(20, modifierIterations))
	table.insert(results, benchmarkPoolOperations(iterations))
	table.insert(results, benchmarkPercentModifier(iterations))
	table.insert(results, benchmarkInvalidateAllCaches(10, 250))
	table.insert(results, benchmarkInvalidateAllCaches(40, 250))

	print("=== Stats Profiler Complete ===\n")
	return results
end

return TestStatsProfiler
