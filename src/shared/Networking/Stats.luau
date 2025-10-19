--!strict
-- Lightweight instrumentation accumulator for the networking layer.

export type Counter = {
	count: number,
}

export type LatencySample = {
	count: number,
	total: number,
	min: number,
	max: number,
}

export type Snapshot = {
	counters: { [string]: Counter },
	latency: { [string]: LatencySample },
}

type StatsImpl = {
	_counters: { [string]: Counter },
	_latency: { [string]: LatencySample },
}

local Stats = {}
Stats.__index = Stats

function Stats.new(): StatsImpl
	local self = setmetatable({
		_counters = {} :: { [string]: Counter },
		_latency = {} :: { [string]: LatencySample },
	} :: StatsImpl, Stats) :: any
	return self :: StatsImpl
end

local function touchCounter(self: StatsImpl, key: string): Counter
	local counter = self._counters[key]
	if not counter then
		counter = { count = 0 }
		self._counters[key] = counter
	end
	return counter
end

function Stats:increment(key: string, amount: number?)
	local counter = touchCounter(self, key)
	local delta = amount or 1
	counter.count += delta
end

local function touchLatency(self: StatsImpl, key: string): LatencySample
	local record = self._latency[key]
	if not record then
		record = {
			count = 0,
			total = 0,
			min = math.huge,
			max = -math.huge,
		}
		self._latency[key] = record
	end
	return record
end

function Stats:observeLatency(key: string, value: number)
	local record = touchLatency(self, key)
	record.count += 1
	record.total += value
	if value < record.min then
		record.min = value
	end
	if value > record.max then
		record.max = value
	end
end

function Stats:reset()
	table.clear(self._counters)
	table.clear(self._latency)
end

local function cloneCounters(source: { [string]: Counter }): { [string]: Counter }
	local copy = {}
	for key, value in pairs(source) do
		copy[key] = { count = value.count }
	end
	return copy
end

local function cloneLatency(source: { [string]: LatencySample }): { [string]: LatencySample }
	local copy = {}
	for key, value in pairs(source) do
		copy[key] = {
			count = value.count,
			total = value.total,
			min = value.min,
			max = value.max,
		}
	end
	return copy
end

function Stats:snapshot(): Snapshot
	return {
		counters = cloneCounters(self._counters),
		latency = cloneLatency(self._latency),
	}
end

function Stats:dump()
	local snap = self:snapshot()
	print("[Networking::Stats] Counters")
	for key, counter in pairs(snap.counters) do
		print(`  {key}: {counter.count}`)
	end
	print("[Networking::Stats] Latency")
	for key, sample in pairs(snap.latency) do
		local record = sample :: LatencySample
		local avg = if record.count > 0 then record.total / record.count else 0
		print(`  {key}: count={record.count}, avg={string.format("%.3f", avg)}, min={string.format("%.3f", record.min)}, max={string.format("%.3f", record.max)}`)
	end
end

return Stats
