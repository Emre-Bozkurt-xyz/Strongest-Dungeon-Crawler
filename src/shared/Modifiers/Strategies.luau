--!strict
-- Strategy helpers for stat modifiers. Strategies encapsulate how a modifier mutates
-- the running value so modifier records can stay declarative.

local Strategies = {}

export type StrategyContext = {
	lastValue: number,
	baseValue: number?,
	stat: any?,
	stats: any?,
	modifier: any,
}

export type Strategy = {
	kind: string,
	apply: (StrategyContext) -> number,
}

Strategies.KINDS = {
	Add = "operation:add",
	Multiply = "operation:multiply",
	PercentOfBase = "operation:percent_of_base",
	PercentOfStat = "operation:percent_of_stat",
	Clamp = "operation:clamp",
}

local function cloneTable<T>(source: { [any]: T }?): { [any]: T }?
	if not source then
		return nil
	end
	return table.clone(source)
end

local function magnitude(modifier: any): number
	local payload = modifier and modifier.payload
	if payload then
		local mag = payload.magnitude or payload.amount or payload.coefficient
		if type(mag) == "number" then
			return mag
		end
	end
	local value = modifier and modifier.value
	if type(value) == "number" then
		return value
	end
	return 0
end

local function resolveMultiplier(modifier: any): number
	local payload = modifier and modifier.payload
	if payload then
		local multiplier = payload.multiplier or payload.factor
		if type(multiplier) == "number" then
			return multiplier
		end
	end
	return 1 + magnitude(modifier)
end

local function define(kind: string, fn: (StrategyContext) -> number): Strategy
	return {
		kind = kind,
		apply = fn,
	}
end

local function resolveStatValue(statObject: any, allStats: any?): number?
	if not statObject then
		return nil
	end
	if typeof(statObject) == "table" then
		local getValue = statObject.getValue
		if typeof(getValue) == "function" then
			return getValue(statObject, allStats)
		end
		local current = statObject.value or statObject.currentValue or statObject.baseValue
		if typeof(current) == "number" then
			return current
		end
	end
	if typeof(statObject) == "number" then
		return statObject
	end
	return nil
end

local ADD = define(Strategies.KINDS.Add, function(context: StrategyContext)
	return context.lastValue + magnitude(context.modifier)
end)

local MULTIPLY = define(Strategies.KINDS.Multiply, function(context: StrategyContext)
	local factor = resolveMultiplier(context.modifier)
	return context.lastValue * factor
end)

local PERCENT_OF_BASE = define(Strategies.KINDS.PercentOfBase, function(context: StrategyContext)
	local baseValue = context.baseValue or context.lastValue
	return context.lastValue + (baseValue * magnitude(context.modifier))
end)

local CLAMP = define(Strategies.KINDS.Clamp, function(context: StrategyContext)
	local payload = context.modifier.payload or {}
	local minValue = payload.min or payload.lower or -math.huge
	local maxValue = payload.max or payload.upper or math.huge
	if type(minValue) ~= "number" then
		minValue = -math.huge
	end
	if type(maxValue) ~= "number" then
		maxValue = math.huge
	end
	if minValue > maxValue then
		minValue, maxValue = maxValue, minValue
	end
	return math.clamp(context.lastValue, minValue, maxValue)
end)

function Strategies.add(): Strategy
	return ADD
end

function Strategies.flat(): Strategy
	return ADD
end

function Strategies.multiply(): Strategy
	return MULTIPLY
end

function Strategies.percent(): Strategy
	return MULTIPLY
end

function Strategies.percentOfBase(): Strategy
	return PERCENT_OF_BASE
end

function Strategies.clamp(): Strategy
	return CLAMP
end

function Strategies.percentOfStat(targetStat: any): Strategy
	local strategy = define(Strategies.KINDS.PercentOfStat, function(context: StrategyContext)
		local stats = context.stats
		if not stats then
			return context.lastValue
		end
		local lookup = targetStat
		local payload = context.modifier.payload
		if payload and payload.targetStat ~= nil then
			lookup = payload.targetStat
		end
		local statObject = lookup and stats[lookup] or nil
		local sourceValue = resolveStatValue(statObject, stats)
		if type(sourceValue) ~= "number" then
			return context.lastValue
		end
		return context.lastValue + (sourceValue * magnitude(context.modifier))
	end)
	return strategy
end

function Strategies.fromKind(kind: string?, params: { [string]: any }?): Strategy?
	if kind == nil then
		return nil
	end
	if kind == Strategies.KINDS.Add then
		return ADD
	elseif kind == Strategies.KINDS.Multiply then
		return MULTIPLY
	elseif kind == Strategies.KINDS.PercentOfBase then
		return PERCENT_OF_BASE
	elseif kind == Strategies.KINDS.Clamp then
		return CLAMP
	elseif kind == Strategies.KINDS.PercentOfStat then
		local opts = (cloneTable(params) or {}) :: { [string]: any }
		local targetStat = opts.targetStat
		if targetStat == nil then
			return nil
		end
		return Strategies.percentOfStat(targetStat)
	end
	return nil
end

function Strategies.kindForLegacyType(modifierType: string?): string
	if modifierType == "percent" then
		return Strategies.KINDS.Multiply
	end
	return Strategies.KINDS.Add
end

return Strategies
