-- Slow: a plain slow with no element (Pin Down). `amount` is the share of speed taken (default
-- 30%); a stronger slow replaces a weaker one, a weaker one only refreshes the timer.

local ServerScriptService = game:GetService("ServerScriptService")

local SpeedModifiers = require(ServerScriptService.Server.Movement.SpeedModifiers)

local SOURCE = "status::Slow"
local DEFAULT_AMOUNT = 0.3

local current: { [string]: number } = {}

local function apply(target: string, params: any?)
	local amount = math.clamp((params and params.amount) or DEFAULT_AMOUNT, 0, 0.9)
	if amount >= (current[target] or 0) then
		current[target] = amount
		SpeedModifiers.set(target, SOURCE, 1 - amount)
	end
end

return {
	id = "Slow",
	isHarmful = true,
	duration = 2,
	maxStacks = 1,
	stacking = "aggregate",
	durationPolicy = "refresh",
	defaultParams = { amount = DEFAULT_AMOUNT },
	potencyKeys = { "amount" },
	onApply = function(target: string, _source: string?, params: any?, _stacks: number)
		apply(target, params)
	end,
	onRefresh = function(target: string, _source: string?, params: any?, _stacks: number)
		apply(target, params)
	end,
	onRemove = function(target: string, _source: string?, _stacks: number)
		current[target] = nil
		SpeedModifiers.clear(target, SOURCE)
	end,
}
