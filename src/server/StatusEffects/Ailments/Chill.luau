-- Chill: frost slows. Each hit adds a stack, up to five; each stack slows by `slowPerStack`, up to
-- `maxSlow`, and every new stack refreshes the duration. A target at full stacks is "fully chilled"
-- (what the Freeze passive looks for: StatusEffectsService.getStacks(target, "Chill") == MAX_STACKS).
-- Not strict, like EffectsIndex, to keep effect definitions one shape across files.

local ServerScriptService = game:GetService("ServerScriptService")

local SpeedModifiers = require(ServerScriptService.Server.Movement.SpeedModifiers)

local SOURCE = "status::Chill"
local MAX_STACKS = 5
local DEFAULT_SLOW_PER_STACK = 0.08
local DEFAULT_MAX_SLOW = 0.5

local lastParams: { [string]: any } = {}

local function slowFor(params: any?, stacks: number): number
	local perStack = (params and params.slowPerStack) or DEFAULT_SLOW_PER_STACK
	local maximum = (params and params.maxSlow) or DEFAULT_MAX_SLOW
	return math.min(maximum, perStack * stacks)
end

local function update(target: string, params: any?, stacks: number)
	lastParams[target] = params or lastParams[target]
	SpeedModifiers.set(target, SOURCE, 1 - slowFor(lastParams[target], stacks))
end

return {
	id = "Chill",
	MAX_STACKS = MAX_STACKS,
	isHarmful = true,
	duration = 3,
	maxStacks = MAX_STACKS,
	stacking = "aggregate",
	durationPolicy = "refresh",
	defaultParams = { slowPerStack = DEFAULT_SLOW_PER_STACK, maxSlow = DEFAULT_MAX_SLOW },
	potencyKeys = { "slowPerStack", "maxSlow" },
	onApply = function(target: string, _source: string?, params: any?, stacks: number)
		update(target, params, stacks)
	end,
	onRefresh = function(target: string, _source: string?, params: any?, stacks: number)
		update(target, params, stacks)
	end,
	onRemove = function(target: string, _source: string?, _stacks: number)
		lastParams[target] = nil
		SpeedModifiers.clear(target, SOURCE)
	end,
}
