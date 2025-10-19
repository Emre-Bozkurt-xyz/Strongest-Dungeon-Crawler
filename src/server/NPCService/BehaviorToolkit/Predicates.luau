--!strict
local Predicates = {}

export type BehaviorContext = {
	behavior: any,
	movement: any?,
	combat: any?,
	damageable: any?,
	model: Model,
	now: number,
	deltaTime: number,
	memory: { [string]: any },
	config: { [string]: any },
}

local function coerce(predicate: ((BehaviorContext) -> boolean) | boolean): (BehaviorContext) -> boolean
	if type(predicate) == "function" then
		return predicate :: (BehaviorContext) -> boolean
	end
	local result = predicate == true
	return function(_ctx: BehaviorContext): boolean
		return result
	end
end

function Predicates.always(value: boolean?): (BehaviorContext) -> boolean
	return coerce(value ~= false)
end

function Predicates.never(): (BehaviorContext) -> boolean
	return coerce(false)
end

function Predicates.invert(predicate: ((BehaviorContext) -> boolean) | boolean): (BehaviorContext) -> boolean
	local fn = coerce(predicate)
	return function(ctx: BehaviorContext): boolean
		return not fn(ctx)
	end
end

function Predicates.all(predicates: { ((BehaviorContext) -> boolean) | boolean }): (BehaviorContext) -> boolean
	return function(ctx: BehaviorContext): boolean
		for _, predicate in ipairs(predicates) do
			if not coerce(predicate)(ctx) then
				return false
			end
		end
		return true
	end
end

function Predicates.any(predicates: { ((BehaviorContext) -> boolean) | boolean }): (BehaviorContext) -> boolean
	return function(ctx: BehaviorContext): boolean
		for _, predicate in ipairs(predicates) do
			if coerce(predicate)(ctx) then
				return true
			end
		end
		return false
	end
end

function Predicates.hasTarget(): (BehaviorContext) -> boolean
	return function(ctx: BehaviorContext): boolean
		return ctx.behavior:hasTarget()
	end
end

function Predicates.noTarget(): (BehaviorContext) -> boolean
	return Predicates.invert(Predicates.hasTarget())
end

function Predicates.targetWithinAttackRange(): (BehaviorContext) -> boolean
	return function(ctx: BehaviorContext): boolean
		return ctx.behavior:isTargetWithinAttackRange()
	end
end

function Predicates.targetBeyondAttackRange(): (BehaviorContext) -> boolean
	return function(ctx: BehaviorContext): boolean
		if not ctx.behavior:hasTarget() then
			return false
		end
		return not ctx.behavior:isTargetWithinAttackRange()
	end
end

function Predicates.targetWithinDistance(distance: number): (BehaviorContext) -> boolean
	return function(ctx: BehaviorContext): boolean
		return ctx.behavior:isTargetWithinDistance(distance)
	end
end

function Predicates.targetBeyondDistance(distance: number): (BehaviorContext) -> boolean
	return Predicates.invert(Predicates.targetWithinDistance(distance))
end

function Predicates.healthBelow(fraction: number): (BehaviorContext) -> boolean
	return function(ctx: BehaviorContext): boolean
		return ctx.behavior:getHealthFraction() <= fraction
	end
end

function Predicates.healthAbove(fraction: number): (BehaviorContext) -> boolean
	return function(ctx: BehaviorContext): boolean
		return ctx.behavior:getHealthFraction() >= fraction
	end
end

function Predicates.shouldFlee(): (BehaviorContext) -> boolean
	return function(ctx: BehaviorContext): boolean
		local threshold = ctx.config.fleeHealthThreshold or 0
		return ctx.behavior:getHealthFraction() <= threshold
	end
end

function Predicates.healthRecovered(): (BehaviorContext) -> boolean
	return function(ctx: BehaviorContext): boolean
		local threshold = ctx.config.resumeHealthThreshold or 1
		return ctx.behavior:getHealthFraction() >= threshold
	end
end

function Predicates.outsideLeash(): (BehaviorContext) -> boolean
	return function(ctx: BehaviorContext): boolean
		local leash = ctx.config.leashRadius or math.huge
		return ctx.behavior:distanceFromSpawn() > leash
	end
end

function Predicates.outsideChase(): (BehaviorContext) -> boolean
	return function(ctx: BehaviorContext): boolean
		local chase = ctx.config.maxChaseDistance or math.huge
		if chase == math.huge then
			return false
		end
		local hysteresis = ctx.config.chaseHysteresis or 0
		return ctx.behavior:distanceFromSpawn() > (chase + hysteresis)
	end
end

function Predicates.insideChase(): (BehaviorContext) -> boolean
	return function(ctx: BehaviorContext): boolean
		local chase = ctx.config.maxChaseDistance or math.huge
		if chase == math.huge then
			return true
		end
		return ctx.behavior:distanceFromSpawn() <= chase
	end
end

function Predicates.reachedSpawn(tolerance: number?): (BehaviorContext) -> boolean
	local epsilon = tolerance or 4
	return function(ctx: BehaviorContext): boolean
		return ctx.behavior:distanceFromSpawn() <= epsilon
	end
end

function Predicates.idleHoldExpired(): (BehaviorContext) -> boolean
	return function(ctx: BehaviorContext): boolean
		return ctx.behavior:isIdleHoldExpired(ctx.now)
	end
end

function Predicates.patrolEnabled(): (BehaviorContext) -> boolean
	return function(ctx: BehaviorContext): boolean
		return ctx.config.enablePatrol ~= false
	end
end

function Predicates.patrolDisabled(): (BehaviorContext) -> boolean
	return Predicates.invert(Predicates.patrolEnabled())
end

function Predicates.dead(): (BehaviorContext) -> boolean
	return function(ctx: BehaviorContext): boolean
		return ctx.behavior:isDead()
	end
end

function Predicates.timeInStateAtLeast(seconds: number): (BehaviorContext) -> boolean
	return function(ctx: BehaviorContext): boolean
		return ctx.behavior:timeInState(ctx.now) >= seconds
	end
end

function Predicates.targetLost(): (BehaviorContext) -> boolean
	return function(ctx: BehaviorContext): boolean
		return not ctx.behavior:hasTarget()
	end
end

function Predicates.isReturningHome(): (BehaviorContext) -> boolean
	return function(ctx: BehaviorContext): boolean
		return ctx.behavior:isReturningHome()
	end
end

function Predicates.notReturningHome(): (BehaviorContext) -> boolean
	return Predicates.invert(Predicates.isReturningHome())
end

return Predicates
