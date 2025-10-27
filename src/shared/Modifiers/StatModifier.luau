--!strict
-- Example of how a class-based modifier system could look. Strategies let callers
-- choose how values are transformed without branching here.

local Strategies = require(script.Parent.Strategies)

local StatModifier = {}
StatModifier.__index = StatModifier

type Strategy = Strategies.Strategy
type StrategyContext = Strategies.StrategyContext

local function cloneArray(list: { any }?): { any }?
	if not list then
		return nil
	end
	return table.clone(list)
end

export type ModifierConfig = {
	value: number?,
	type: "flat" | "percent"?,
	condition: ((stats: any, context: StrategyContext?) -> boolean)?,
	description: string?,
	source_id: string,
	strategy: Strategy?,
	strategyKind: string?,
	strategyParams: { [string]: any }?,
	payload: { [string]: any }?,
	metadata: { [string]: any }?,
	tags: { string }?,
	stackGroup: string?,
	priority: number?,
	duration: number?,
	expiresAt: number?,
}

local function resolveStrategy(config: ModifierConfig): Strategy
	if config.strategy then
		return config.strategy
	end

	local strategyKind = config.strategyKind
	if not strategyKind then
		strategyKind = Strategies.kindForLegacyType(config.type)
	end

	if not strategyKind then
		error(`Modifier {config.source_id} is missing a strategy. Provide 'strategy' or 'strategyKind'.`)
	end

	local fromKind = Strategies.fromKind(strategyKind, config.strategyParams)
	if not fromKind then
		error(`Unknown strategy kind '{strategyKind}' for modifier {config.source_id}`)
	end

	return fromKind
end

local function inferLegacyType(strategyKind: string?): "flat" | "percent"
	if strategyKind == Strategies.KINDS.Multiply or strategyKind == Strategies.KINDS.PercentOfBase or strategyKind == Strategies.KINDS.PercentOfStat then
		return "percent"
	end
	return "flat"
end

local function coerceContext(self, arg1, arg2, arg3): StrategyContext
	if typeof(arg1) == "table" then
		local provided = arg1 :: any
		local context = table.clone(provided)
		context.modifier = self
		if context.baseValue == nil and arg3 and typeof(arg3) == "table" then
			local stat = arg3 :: any
			if stat and stat.baseValue ~= nil then
				context.baseValue = stat.baseValue
			end
		end
		if context.stats == nil then
			context.stats = arg2
		end
		if context.stat == nil then
			context.stat = arg3
		end
		if context.lastValue == nil then
			context.lastValue = 0
		end
		return context :: StrategyContext
	end

	local lastValue = arg1 :: number
	local stats = arg2
	local stat = arg3
	local baseValue = nil
	if stat and typeof(stat) == "table" then
		local statTable = stat :: any
		baseValue = statTable.baseValue
	end

	return {
		lastValue = lastValue,
		baseValue = baseValue,
		stat = stat,
		stats = stats,
		modifier = self,
	}
end

-- Create a new modifier
function StatModifier.new(config: ModifierConfig)
	assert(config.source_id ~= nil and config.source_id ~= "", "StatModifier.new requires source_id")
	local strategy = resolveStrategy(config)

	local payload = config.payload and table.clone(config.payload) or {}
	local metadata = config.metadata and table.clone(config.metadata) or nil
	local strategyParams = config.strategyParams and table.clone(config.strategyParams) or nil

	local self = setmetatable({
		value = config.value,
		type = config.type or inferLegacyType(strategy.kind),
		condition = config.condition,
		description = config.description or "",
		source_id = config.source_id,
		isActive = true,
		modifierType = "StatModifier", -- Identify modifier type for serialization
		strategy = strategy,
		strategyKind = strategy.kind,
		strategyParams = strategyParams,
		payload = payload,
		metadata = metadata,
		tags = cloneArray(config.tags),
		stackGroup = config.stackGroup,
		priority = config.priority or 0,
		duration = config.duration,
		expiresAt = config.expiresAt,
	}, StatModifier)

	return self
end

-- Calculate the modifier value dynamically
function StatModifier:apply(arg1, arg2, arg3): number
	local context = coerceContext(self, arg1, arg2, arg3)

	if not self.isActive then
		return context.lastValue
	end

	if self.condition and not self.condition(context.stats, context) then
		return context.lastValue
	end

	local strategy = self.strategy
	if not strategy then
		error(`Modifier {self.source_id} missing strategy during apply`)
	end

	context.modifier = self
	return strategy.apply(context)
end

-- Modify the value
function StatModifier:modifyValue(newValue: number)
	self.value = newValue

	local payload = self.payload
	if payload then
		if payload.magnitude ~= nil then
			payload.magnitude = newValue
		end
		if payload.amount ~= nil then
			payload.amount = newValue
		end
		if payload.coefficient ~= nil then
			payload.coefficient = newValue
		end
		if self.strategyKind == Strategies.KINDS.Multiply then
			payload.multiplier = 1 + newValue
		end
	end
end

-- Enable/disable the modifier
function StatModifier:setActive(active: boolean)
	self.isActive = active
end

return StatModifier
