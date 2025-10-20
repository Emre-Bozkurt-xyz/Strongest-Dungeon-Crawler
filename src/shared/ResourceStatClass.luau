--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PoolStat = require(ReplicatedStorage.Shared.PoolStatClass)

export type ResourceThresholdEvent = {
	thresholdId: string,
	currentValue: number,
	maxValue: number,
	percent: number,
	previousValue: number,
	comparison: string,
	value: number,
}

export type ResourceThresholdConfig = {
	value: number,
	type: "absolute" | "percentage"?,
	comparison: "<" | "<=" | ">" | ">="?,
	once: boolean?,
	callback: ((any, ResourceThresholdEvent) -> ())?,
	visibleToClient: boolean?,
}

export type ResourceConfig = {
	baseValue: number,
	minValue: number?,
	maxValue: number?,
	name: string,
	description: string?,
	startAtMax: boolean?,
	startingValue: number?,
	regenerationRate: number?,
	regenPaused: boolean?,
	depletionThreshold: number?,
	thresholds: { [string]: ResourceThresholdConfig }?,
}

type ThresholdRecord = {
	id: string,
	type: "absolute" | "percentage",
	value: number,
	comparison: "<" | "<=" | ">" | ">=",
	once: boolean,
	callback: ((any, ResourceThresholdEvent) -> ())?,
	isMet: boolean,
	disabled: boolean,
	visibleToClient: boolean,
}

type CallbackRegistry = { [string]: { [string]: (any, any) -> () } }

type PendingEvent = {
	event: string,
	data: any,
}

local ResourceStat = {}
ResourceStat.__index = ResourceStat
setmetatable(ResourceStat, { __index = PoolStat })

local DEFAULT_COMPARISON: "<" | "<=" | ">" | ">=" = "<="
local EPSILON = 1e-4

local function cloneTable(source: any): any
	if type(source) ~= "table" then
		return source
	end
	local result = {}
	for key, value in pairs(source) do
		result[key] = cloneTable(value)
	end
	return result
end

local function compare(lhs: number, op: string, rhs: number): boolean
	if op == "<" then
		return lhs < rhs
	elseif op == "<=" then
		return lhs <= rhs
	elseif op == ">" then
		return lhs > rhs
	elseif op == ">=" then
		return lhs >= rhs
	end
	return false
end

local function buildThreshold(id: string, config: ResourceThresholdConfig): ThresholdRecord
	return {
		id = id,
		type = config.type or "absolute",
		value = config.value,
		comparison = config.comparison or DEFAULT_COMPARISON,
		once = config.once == true,
		callback = config.callback,
		isMet = false,
		disabled = false,
		visibleToClient = config.visibleToClient ~= false,
	}
end

local function thresholdSnapshot(threshold: ThresholdRecord)
	return {
		id = threshold.id,
		type = threshold.type,
		value = threshold.value,
		comparison = threshold.comparison,
		once = threshold.once,
		isMet = threshold.isMet,
		disabled = threshold.disabled,
		visibleToClient = threshold.visibleToClient,
	}
end

function ResourceStat.new(config: ResourceConfig)
	local base = PoolStat.new({
		baseValue = config.baseValue,
		minValue = config.minValue,
		maxValue = config.maxValue,
		name = config.name,
		description = config.description,
		startAtMax = config.startAtMax,
	})
	setmetatable(base, ResourceStat)

	base.statType = "resource"
	base._regenerationRate = config.regenerationRate or 0
	base._regenerationPaused = config.regenPaused == true
	base._regenResumeTime = nil :: number?
	base._depletionThreshold = config.depletionThreshold or 0
	base._thresholds = {} :: { [string]: ThresholdRecord }
	base._pendingEvents = {} :: { PendingEvent }
	base._callbacks = {
		valueChanged = {},
		depleted = {},
		restored = {},
		threshold = {},
		regenerated = {},
		metadataChanged = {},
	} :: CallbackRegistry

	if config.startingValue ~= nil then
		base.currentValue = config.startingValue
	end

	if config.thresholds then
		for thresholdId, thresholdConfig in pairs(config.thresholds) do
			base:_addThreshold(thresholdId, thresholdConfig, true)
		end
	end

	return base
end

function ResourceStat:getRegenerationRate(): number
	return self._regenerationRate
end

function ResourceStat:setRegenerationRate(rate: number, skipEvent: boolean?)
	if math.abs(rate - self._regenerationRate) <= EPSILON then
		self._regenerationRate = rate
		return
	end
	self._regenerationRate = rate
	if not skipEvent then
		self:_emitEvent("metadataChanged", { kind = "regenerationRate", value = rate })
	end
end

function ResourceStat:_setRegenerationPausedInternal(paused: boolean, resumeTime: number?)
	self._regenerationPaused = paused
	self._regenResumeTime = resumeTime
end

function ResourceStat:pauseRegeneration(duration: number?)
	local resumeAt = if duration and duration > 0 then os.clock() + duration else nil
	self:_setRegenerationPausedInternal(true, resumeAt)
	self:_emitEvent("metadataChanged", {
		kind = "regenerationPaused",
		value = true,
		resumeTime = resumeAt,
	})
end

function ResourceStat:resumeRegeneration()
	if not self._regenerationPaused then
		return
	end
	self:_setRegenerationPausedInternal(false, nil)
	self:_emitEvent("metadataChanged", {
		kind = "regenerationPaused",
		value = false,
	})
end

function ResourceStat:isRegenerationPaused(): boolean
	if self._regenerationPaused and self._regenResumeTime then
		if os.clock() >= (self._regenResumeTime :: number) then
			self:_setRegenerationPausedInternal(false, nil)
		end
	end
	return self._regenerationPaused
end

function ResourceStat:setDepletionThreshold(threshold: number, skipEvent: boolean?)
	if math.abs(threshold - self._depletionThreshold) <= EPSILON then
		self._depletionThreshold = threshold
		return
	end
	self._depletionThreshold = threshold
	if not skipEvent then
		self:_emitEvent("metadataChanged", { kind = "depletionThreshold", value = threshold })
	end
end

function ResourceStat:getDepletionThreshold(): number
	return self._depletionThreshold
end

function ResourceStat:_addThreshold(thresholdId: string, config: ResourceThresholdConfig, skipEvent: boolean?)
	local record = buildThreshold(thresholdId, config)
	self._thresholds[thresholdId] = record
	if not skipEvent then
		self:_emitEvent("metadataChanged", {
			kind = "thresholdAdded",
			threshold = thresholdSnapshot(record),
		})
	end
	return record
end

function ResourceStat:addThreshold(thresholdId: string, config: ResourceThresholdConfig)
	return self:_addThreshold(thresholdId, config, false)
end

function ResourceStat:removeThreshold(thresholdId: string, skipEvent: boolean?)
	if not self._thresholds[thresholdId] then
		return false
	end
	self._thresholds[thresholdId] = nil
	if not skipEvent then
		self:_emitEvent("metadataChanged", {
			kind = "thresholdRemoved",
			thresholdId = thresholdId,
		})
	end
	return true
end

function ResourceStat:clearThresholds()
	for thresholdId in pairs(self._thresholds) do
		self._thresholds[thresholdId] = nil
	end
end

function ResourceStat:getThresholdsSnapshot()
	local snapshot = {}
	for thresholdId, threshold in pairs(self._thresholds) do
		snapshot[thresholdId] = thresholdSnapshot(threshold)
	end
	return snapshot
end

function ResourceStat:setThresholdsSnapshot(snapshot: { [string]: any })
	self:clearThresholds()
	for thresholdId, data in pairs(snapshot) do
		local record = self:_addThreshold(thresholdId, {
			value = data.value,
			type = data.type,
			comparison = data.comparison,
			once = data.once,
			visibleToClient = data.visibleToClient,
		}, true)
		record.isMet = data.isMet == true
		record.disabled = data.disabled == true
	end
end

function ResourceStat:registerCallback(eventName: string, callbackId: string, callback: (any, any) -> ())
	local list = self._callbacks[eventName]
	if not list then
		list = {}
		self._callbacks[eventName] = list
	end
	list[callbackId] = callback
end

function ResourceStat:unregisterCallback(eventName: string, callbackId: string)
	local list = self._callbacks[eventName]
	if not list then
		return
	end
	list[callbackId] = nil
end

function ResourceStat:_emitEvent(eventName: string, data: any, shouldQueue: boolean?)
	if shouldQueue ~= false then
		table.insert(self._pendingEvents, {
			event = eventName,
			data = cloneTable(data),
		})
	end
	local list = self._callbacks[eventName]
	if list then
		for _, callback in pairs(list) do
			callback(self, data)
		end
	end
end

function ResourceStat:consumeQueuedEvents()
	if #self._pendingEvents == 0 then
		return {}
	end
	local events = self._pendingEvents
	self._pendingEvents = {}
	return events
end

local function computePercent(currentValue: number, maxValue: number): number
	if maxValue <= 0 then
		return 0
	end
	return (currentValue / maxValue) * 100
end

function ResourceStat:_evaluateDepletion(previousValue: number, newValue: number, maxValue: number)
	local threshold: number = self._depletionThreshold
	local wasDepleted = previousValue <= threshold + EPSILON
	local isDepleted = newValue <= threshold + EPSILON
	if isDepleted and not wasDepleted then
		self:_emitEvent("depleted", {
			previousValue = previousValue,
			currentValue = newValue,
			maxValue = maxValue,
		})
	elseif wasDepleted and not isDepleted then
		self:_emitEvent("restored", {
			previousValue = previousValue,
			currentValue = newValue,
			maxValue = maxValue,
		})
	end
end

function ResourceStat:_evaluateThresholds(previousValue: number, newValue: number, maxValue: number)
	local percent = computePercent(newValue, maxValue)
	for _, threshold in pairs(self._thresholds) do
		if not threshold.disabled then
			local valueToCompare = if threshold.type == "percentage" then percent else newValue
			local comparisonTarget = threshold.value
			local isMet = compare(valueToCompare, threshold.comparison, comparisonTarget)
			if isMet and not threshold.isMet then
				local payload: ResourceThresholdEvent = {
					thresholdId = threshold.id,
					currentValue = newValue,
					maxValue = maxValue,
					percent = percent,
					previousValue = previousValue,
					comparison = threshold.comparison,
					value = threshold.value,
				}
				self:_emitEvent("threshold", payload)
				if threshold.callback then
					threshold.callback(self, payload)
				end
				if threshold.once then
					threshold.disabled = true
				end
			end
			threshold.isMet = isMet
		end
	end
end

function ResourceStat:_onValueChanged(previousValue: number, newValue: number, allStats: any?)
	local maxValue = self:getValue(allStats)
	local delta = newValue - previousValue
	self:_emitEvent("valueChanged", {
		previousValue = previousValue,
		currentValue = newValue,
		delta = delta,
		maxValue = maxValue,
		percent = computePercent(newValue, maxValue),
	})
	self:_evaluateDepletion(previousValue, newValue, maxValue)
	self:_evaluateThresholds(previousValue, newValue, maxValue)
	if delta > EPSILON and self._regenerationRate > 0 then
		self:_emitEvent("regenerated", {
			previousValue = previousValue,
			currentValue = newValue,
			delta = delta,
			maxValue = maxValue,
			percent = computePercent(newValue, maxValue),
		})
	end
end

function ResourceStat:setCurrentValue(value: number, allStats: any?): number
	local previousValue = self.currentValue :: number
	local newValue: number = PoolStat.setCurrentValue(self, value, allStats)
	if math.abs(newValue - previousValue) > EPSILON then
		self:_onValueChanged(previousValue, newValue, allStats)
	end
	return newValue
end

function ResourceStat:tick(deltaTime: number, allStats: any?): boolean
	if deltaTime <= 0 then
		return false
	end
	if math.abs(self._regenerationRate) <= EPSILON then
		return false
	end
	if self:isRegenerationPaused() then
		return false
	end
	local previousValue = self.currentValue :: number
	local change = self._regenerationRate * deltaTime
	local newValue: number = self:setCurrentValue(previousValue + change, allStats)
	return math.abs(newValue - previousValue) > EPSILON
end

function ResourceStat:getMetadataSnapshot(): any
	return {
		regenerationRate = self._regenerationRate,
		regenerationPaused = self._regenerationPaused,
		resumeTime = self._regenResumeTime,
		depletionThreshold = self._depletionThreshold,
		thresholds = self:getThresholdsSnapshot(),
	}
end

function ResourceStat:applyMetadataSnapshot(snapshot: any)
	if snapshot.regenerationRate ~= nil then
		self:setRegenerationRate(snapshot.regenerationRate, true)
	end
	if snapshot.regenerationPaused ~= nil then
		self:_setRegenerationPausedInternal(snapshot.regenerationPaused, snapshot.resumeTime)
	end
	if snapshot.depletionThreshold ~= nil then
		self:setDepletionThreshold(snapshot.depletionThreshold, true)
	end
	if snapshot.thresholds then
		self:setThresholdsSnapshot(snapshot.thresholds)
	end
end

function ResourceStat:applyRemoteEvent(eventName: string, data: any)
	self:_emitEvent(eventName, data, false)
end

return ResourceStat
