--!strict
-- Centralised modifier factories produce strategy-backed modifiers with consistent metadata.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StatModifier = require(ReplicatedStorage.Shared.Modifiers.StatModifier)
local Strategies = require(ReplicatedStorage.Shared.Modifiers.Strategies)

export type StrategyContext = Strategies.StrategyContext

export type BaseOptions = {
	sourceId: string,
	description: string?,
	condition: ((stats: any, context: StrategyContext?) -> boolean)?,
	tags: { string }?,
	stackGroup: string?,
	priority: number?,
	metadata: { [string]: any }?,
	duration: number?,
	expiresAt: number?,
}

export type FlatOptions = BaseOptions & {
	amount: number,
	payload: { [string]: any }?,
}

export type PercentOptions = BaseOptions & {
	percent: number,
	payload: { [string]: any }?,
}

export type PercentOfStatOptions = PercentOptions & {
	targetStat: any,
}

export type ClampOptions = BaseOptions & {
	min: number?,
	max: number?,
	payload: { [string]: any }?,
}

local DEFAULT_PRIORITIES = {
	[Strategies.KINDS.Add] = 100,
	[Strategies.KINDS.PercentOfBase] = 200,
	[Strategies.KINDS.PercentOfStat] = 220,
	[Strategies.KINDS.Multiply] = 300,
	[Strategies.KINDS.Clamp] = 1000,
}

local function cloneArray<T>(list: { T }?): { T }?
	if not list then
		return nil
	end
	return table.clone(list)
end

local function ensureSourceId(options: BaseOptions)
	assert(options.sourceId ~= nil and options.sourceId ~= "", "Modifier factory requires sourceId")
end

local ModifierFactories = {}

local function resolveMagnitudeFromPayload(payload: { [string]: any }?): number?
	if not payload then
		return nil
	end
	local candidates = { "magnitude", "amount", "coefficient", "value", "percent" }
	for _, key in ipairs(candidates) do
		local candidate = payload[key]
		if typeof(candidate) == "number" then
			return candidate
		end
	end
	return nil
end

local function resolvePercentValue(serialized: { [string]: any }): number
	if typeof(serialized.value) == "number" then
		return serialized.value
	end
	local payload = serialized.payload
	local payloadPercent = resolveMagnitudeFromPayload(payload)
	if payloadPercent ~= nil then
		return payloadPercent
	end
	if payload and typeof(payload.multiplier) == "number" then
		return payload.multiplier - 1
	end
	return 0
end

local function resolveFlatAmount(serialized: { [string]: any }): number
	if typeof(serialized.value) == "number" then
		return serialized.value
	end
	local fromPayload = resolveMagnitudeFromPayload(serialized.payload)
	if fromPayload ~= nil then
		return fromPayload
	end
	return 0
end

local function resolveClampBounds(payload: { [string]: any }?): (number?, number?)
	if not payload then
		return nil, nil
	end
	local minValue = payload.min or payload.lower
	local maxValue = payload.max or payload.upper
	if typeof(minValue) ~= "number" then
		minValue = nil
	end
	if typeof(maxValue) ~= "number" then
		maxValue = nil
	end
	return minValue, maxValue
end

function ModifierFactories.flatAdd(options: FlatOptions)
	ensureSourceId(options)
	local payload: { [string]: any }
	if options.payload then
		payload = table.clone(options.payload)
	else
		payload = {}
	end
	payload.magnitude = options.amount

	return StatModifier.new({
		value = options.amount,
		source_id = options.sourceId,
		description = options.description,
		condition = options.condition,
		strategy = Strategies.add(),
		payload = payload,
		tags = cloneArray(options.tags),
		stackGroup = options.stackGroup,
		priority = options.priority or DEFAULT_PRIORITIES[Strategies.KINDS.Add],
		metadata = options.metadata,
		duration = options.duration,
		expiresAt = options.expiresAt,
	})
end

function ModifierFactories.percentBuff(options: PercentOptions)
	ensureSourceId(options)
	local payload: { [string]: any }
	if options.payload then
		payload = table.clone(options.payload)
	else
		payload = {}
	end
	payload.coefficient = options.percent
	if payload.multiplier == nil then
		payload.multiplier = 1 + options.percent
	end

	return StatModifier.new({
		value = options.percent,
		source_id = options.sourceId,
		description = options.description,
		condition = options.condition,
		strategy = Strategies.multiply(),
		payload = payload,
		tags = cloneArray(options.tags),
		stackGroup = options.stackGroup,
		priority = options.priority or DEFAULT_PRIORITIES[Strategies.KINDS.Multiply],
		metadata = options.metadata,
		duration = options.duration,
		expiresAt = options.expiresAt,
	})
end

function ModifierFactories.percentOfBase(options: PercentOptions)
	ensureSourceId(options)
	local payload: { [string]: any }
	if options.payload then
		payload = table.clone(options.payload)
	else
		payload = {}
	end
	payload.magnitude = options.percent

	return StatModifier.new({
		value = options.percent,
		source_id = options.sourceId,
		description = options.description,
		condition = options.condition,
		strategy = Strategies.percentOfBase(),
		payload = payload,
		tags = cloneArray(options.tags),
		stackGroup = options.stackGroup,
		priority = options.priority or DEFAULT_PRIORITIES[Strategies.KINDS.PercentOfBase],
		metadata = options.metadata,
		duration = options.duration,
		expiresAt = options.expiresAt,
	})
end

function ModifierFactories.percentOfStat(options: PercentOfStatOptions)
	ensureSourceId(options)
	local payload: { [string]: any }
	if options.payload then
		payload = table.clone(options.payload)
	else
		payload = {}
	end
	payload.magnitude = options.percent
	payload.targetStat = options.targetStat

	local modifier = StatModifier.new({
		value = options.percent,
		source_id = options.sourceId,
		description = options.description,
		condition = options.condition,
		strategy = Strategies.percentOfStat(options.targetStat),
		strategyParams = { targetStat = options.targetStat },
		payload = payload,
		tags = cloneArray(options.tags),
		stackGroup = options.stackGroup,
		priority = options.priority or DEFAULT_PRIORITIES[Strategies.KINDS.PercentOfStat],
		metadata = options.metadata,
		duration = options.duration,
		expiresAt = options.expiresAt,
	})

	local modifierRecord = modifier :: any
	modifierRecord.modifierType = "PercentOfStatModifier"
	modifierRecord.targetStat = options.targetStat

	return modifier
end

function ModifierFactories.clamp(options: ClampOptions)
	ensureSourceId(options)
	local payload: { [string]: any }
	if options.payload then
		payload = table.clone(options.payload)
	else
		payload = {}
	end
	if options.min ~= nil then
		payload.min = options.min
	end
	if options.max ~= nil then
		payload.max = options.max
	end

	return StatModifier.new({
		source_id = options.sourceId,
		description = options.description,
		condition = options.condition,
		strategy = Strategies.clamp(),
		payload = payload,
		tags = cloneArray(options.tags),
		stackGroup = options.stackGroup,
		priority = options.priority or DEFAULT_PRIORITIES[Strategies.KINDS.Clamp],
		metadata = options.metadata,
		duration = options.duration,
		expiresAt = options.expiresAt,
	})
end

function ModifierFactories.hydrate(serialized: { [string]: any }): any
	if not serialized then
		return nil
	end
	local sourceId = serialized.source_id
	if typeof(sourceId) ~= "string" or sourceId == "" then
		warn("Attempted to hydrate modifier without a source_id")
		return nil
	end

	local payload = serialized.payload
	local strategyKind = serialized.strategyKind or Strategies.kindForLegacyType(serialized.type)
	local baseOptions: BaseOptions = {
		sourceId = sourceId,
		description = serialized.description,
		condition = nil,
		tags = serialized.tags,
		stackGroup = serialized.stackGroup,
		priority = serialized.priority,
		metadata = serialized.metadata,
		duration = serialized.duration,
		expiresAt = serialized.expiresAt,
	}

	local modifier: any = nil

	if serialized.modifierType == "PercentOfStatModifier" or strategyKind == Strategies.KINDS.PercentOfStat then
		local percent = resolvePercentValue(serialized)
		local params = serialized.strategyParams
		local target = serialized.targetStat
		if target == nil and params then
			target = params.targetStat
		end
		if target == nil and payload then
			target = payload.targetStat
		end
		if target == nil then
			warn(`PercentOfStat modifier {sourceId} missing target stat during hydrate`)
			return nil
		end
		local options: PercentOfStatOptions = {
			sourceId = baseOptions.sourceId,
			description = baseOptions.description,
			condition = baseOptions.condition,
			tags = baseOptions.tags,
			stackGroup = baseOptions.stackGroup,
			priority = baseOptions.priority,
			metadata = baseOptions.metadata,
			duration = baseOptions.duration,
			expiresAt = baseOptions.expiresAt,
			percent = percent,
			payload = payload,
			targetStat = target,
		}
		modifier = ModifierFactories.percentOfStat(options)
	elseif strategyKind == Strategies.KINDS.Multiply then
		local percent = resolvePercentValue(serialized)
		modifier = ModifierFactories.percentBuff({
			sourceId = baseOptions.sourceId,
			description = baseOptions.description,
			condition = baseOptions.condition,
			tags = baseOptions.tags,
			stackGroup = baseOptions.stackGroup,
			priority = baseOptions.priority,
			metadata = baseOptions.metadata,
			duration = baseOptions.duration,
			expiresAt = baseOptions.expiresAt,
			percent = percent,
			payload = payload,
		})
	elseif strategyKind == Strategies.KINDS.PercentOfBase then
		local percent = resolvePercentValue(serialized)
		modifier = ModifierFactories.percentOfBase({
			sourceId = baseOptions.sourceId,
			description = baseOptions.description,
			condition = baseOptions.condition,
			tags = baseOptions.tags,
			stackGroup = baseOptions.stackGroup,
			priority = baseOptions.priority,
			metadata = baseOptions.metadata,
			duration = baseOptions.duration,
			expiresAt = baseOptions.expiresAt,
			percent = percent,
			payload = payload,
		})
	elseif strategyKind == Strategies.KINDS.Clamp then
		local minValue, maxValue = resolveClampBounds(payload)
		modifier = ModifierFactories.clamp({
			sourceId = baseOptions.sourceId,
			description = baseOptions.description,
			condition = baseOptions.condition,
			tags = baseOptions.tags,
			stackGroup = baseOptions.stackGroup,
			priority = baseOptions.priority,
			metadata = baseOptions.metadata,
			duration = baseOptions.duration,
			expiresAt = baseOptions.expiresAt,
			min = minValue,
			max = maxValue,
			payload = payload,
		})
	else
		local amount = resolveFlatAmount(serialized)
		if strategyKind and strategyKind ~= Strategies.KINDS.Add then
			local strategy = Strategies.fromKind(strategyKind, serialized.strategyParams)
			if strategy then
				modifier = StatModifier.new({
					value = amount,
					source_id = baseOptions.sourceId,
					description = baseOptions.description,
					condition = baseOptions.condition,
					strategy = strategy,
					strategyKind = strategyKind,
					strategyParams = serialized.strategyParams,
					payload = payload,
					tags = cloneArray(baseOptions.tags),
					stackGroup = baseOptions.stackGroup,
					priority = baseOptions.priority,
					metadata = baseOptions.metadata,
					duration = baseOptions.duration,
					expiresAt = baseOptions.expiresAt,
				})
			end
		end
		if not modifier then
			modifier = ModifierFactories.flatAdd({
				sourceId = baseOptions.sourceId,
				description = baseOptions.description,
				condition = baseOptions.condition,
				tags = baseOptions.tags,
				stackGroup = baseOptions.stackGroup,
				priority = baseOptions.priority,
				metadata = baseOptions.metadata,
				duration = baseOptions.duration,
				expiresAt = baseOptions.expiresAt,
				amount = amount,
				payload = payload,
			})
		end
	end

	if modifier then
		local modifierRecord = modifier :: any
		if serialized.modifierType then
			modifierRecord.modifierType = serialized.modifierType
		end
		if serialized.strategyParams and modifierRecord.strategyParams == nil then
			modifierRecord.strategyParams = table.clone(serialized.strategyParams)
		end
	end

	return modifier
end

return ModifierFactories
