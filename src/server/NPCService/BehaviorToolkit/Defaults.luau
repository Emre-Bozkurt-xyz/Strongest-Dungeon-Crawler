--!strict
local Predicates = require(script.Parent.Predicates)
local Actions = require(script.Parent.Actions)

export type BehaviorOptions = {
	thinkInterval: number?,
	enablePatrol: boolean?,
	leashRadius: number?,
	maxChaseDistance: number?,
	chaseHysteresis: number?,
	returnHomeResumeDistance: number?,
	repathDistance: number?,
	repathInterval: number?,
	idleHoldMin: number?,
	idleHoldMax: number?,
	fleeHealthThreshold: number?,
	resumeHealthThreshold: number?,
	debugReturnHome: boolean?,
	debugStateTransitions: boolean?,
}

local Defaults = {}

local function resolve(options: BehaviorOptions?): { [string]: any }
	local opts: BehaviorOptions = options or ({} :: BehaviorOptions)
	local resolved = {
		thinkInterval = opts.thinkInterval or 0.25,
		enablePatrol = if opts.enablePatrol ~= nil then opts.enablePatrol else true,
		leashRadius = opts.leashRadius or 32,
		maxChaseDistance = opts.maxChaseDistance or 48,
		chaseHysteresis = opts.chaseHysteresis or 3,
		returnHomeResumeDistance = opts.returnHomeResumeDistance or math.max(0, (opts.leashRadius or 32) * 0.6),
		repathDistance = opts.repathDistance or 6,
		repathInterval = opts.repathInterval or 1.0,
		idleHoldMin = opts.idleHoldMin or 1,
		idleHoldMax = opts.idleHoldMax or 4,
		fleeHealthThreshold = opts.fleeHealthThreshold or 0.15,
		resumeHealthThreshold = opts.resumeHealthThreshold or 0.4,
		debugReturnHome = opts.debugReturnHome == true,
		debugStateTransitions = opts.debugStateTransitions == true,
	}
	return resolved
end

function Defaults.basic(options: BehaviorOptions?): { [string]: any }
	local config = resolve(options)

	local globalTransitions = {
		{
			to = "Dead",
			when = Predicates.dead(),
			actions = { Actions.stopMovement(), Actions.clearTarget() },
			debugLabel = "Global->Dead",
		},
	}
	local states = {}

	states.Idle = {
		onEnter = { Actions.stopMovement(), Actions.scheduleIdleHold() },
		onTick = { Actions.acquireTarget(), Actions.pathHomeIfReturning() },
		transitions = {
			{
				to = "Flee",
				when = Predicates.shouldFlee(),
				actions = { Actions.enableRunning(), Actions.pathToSpawn() },
				debugLabel = "Idle->Flee",
			},
			{
				to = "Seek",
				when = Predicates.hasTarget(),
				actions = { Actions.enableRunning(), Actions.pathToTarget() },
				debugLabel = "Idle->Seek",
			},
			{
				to = "Patrol",
				when = Predicates.all({ Predicates.patrolEnabled(), Predicates.idleHoldExpired(), Predicates.notReturningHome() }),
				actions = { Actions.startPatrol() },
				debugLabel = "Idle->Patrol",
			},
		},
	}

	states.Patrol = {
		onEnter = { Actions.startPatrol() },
		onTick = { Actions.acquireTarget(), Actions.continuePatrol() },
		transitions = {
			{
				to = "Flee",
				when = Predicates.shouldFlee(),
				actions = { Actions.enableRunning(), Actions.pathToSpawn() },
				debugLabel = "Patrol->Flee",
			},
			{
				to = "Seek",
				when = Predicates.hasTarget(),
				actions = { Actions.clearReturningHome(), Actions.enableRunning(), Actions.pathToTarget() },
				debugLabel = "Patrol->Seek",
			},
			{
				to = "Recover",
				when = Predicates.outsideLeash(),
				actions = { Actions.enableWalking(), Actions.markReturningHome(), Actions.pathToSpawn() },
				debugLabel = "Patrol->Recover",
			},
			{
				to = "Idle",
				when = Predicates.any({ Predicates.patrolDisabled(), Predicates.timeInStateAtLeast(6) }),
				actions = { Actions.stopMovement(), Actions.scheduleIdleHold() },
				debugLabel = "Patrol->Idle",
			},
		},
	}

	states.Seek = {
		onEnter = { Actions.clearReturningHome(), Actions.enableRunning(), Actions.pathToTarget() },
		onTick = { Actions.acquireTarget(), Actions.pathToTarget() },
		transitions = {
			{
				to = "Flee",
				when = Predicates.shouldFlee(),
				actions = { Actions.pathToSpawn() },
				debugLabel = "Seek->Flee",
			},
			{
				to = "Engage",
				when = Predicates.targetWithinAttackRange(),
				actions = { Actions.stopMovement() },
				debugLabel = "Seek->Engage",
			},
			{
				to = "Recover",
				when = Predicates.targetLost(),
				actions = { Actions.clearTarget(), Actions.enableWalking(), Actions.clearReturningHome(), Actions.pathToSpawn() },
				debugLabel = "Seek->Recover (TargetLost)",
			},
			{
				to = "Recover",
				when = Predicates.all({ Predicates.outsideChase(), Predicates.targetBeyondAttackRange() }),
				actions = { Actions.clearTarget(), Actions.enableWalking(), Actions.markReturningHome(), Actions.pathToSpawn() },
				debugLabel = "Seek->Recover (OutsideChase)",
			},
		},
	}

	states.Engage = {
		onEnter = { Actions.stopMovement() },
		onTick = { Actions.acquireTarget(), Actions.attack() },
		transitions = {
			{
				to = "Flee",
				when = Predicates.shouldFlee(),
				actions = { Actions.clearTarget(), Actions.enableRunning(), Actions.pathToSpawn() },
				debugLabel = "Engage->Flee",
			},
			{
				to = "Seek",
				when = Predicates.targetBeyondAttackRange(),
				actions = { Actions.enableRunning() },
				debugLabel = "Engage->Seek",
			},
			{
				to = "Recover",
				when = Predicates.targetLost(),
				actions = { Actions.clearTarget(), Actions.enableWalking(), Actions.clearReturningHome(), Actions.pathToSpawn() },
				debugLabel = "Engage->Recover (TargetLost)",
			},
			{
				to = "Recover",
				when = Predicates.outsideChase(),
				actions = { Actions.clearTarget(), Actions.enableWalking(), Actions.markReturningHome(), Actions.pathToSpawn() },
				debugLabel = "Engage->Recover (OutsideChase)",
			},
		},
	}

	states.Flee = {
		onEnter = { Actions.enableRunning(), Actions.pathToSpawn() },
		onTick = { Actions.pathToSpawn() },
		transitions = {
			{
				to = "Recover",
				when = Predicates.all({ Predicates.healthRecovered(), Predicates.reachedSpawn() }),
				actions = { Actions.enableWalking(), Actions.stopMovement(), Actions.scheduleIdleHold() },
				debugLabel = "Flee->Recover",
			},
		},
	}

	states.Recover = {
		onEnter = { Actions.enableWalking(), Actions.stopMovement(), Actions.scheduleIdleHold() },
		onTick = { Actions.acquireTarget(), Actions.pathHomeIfReturning() },
		transitions = {
			{
				to = "Flee",
				when = Predicates.shouldFlee(),
				actions = { Actions.enableRunning(), Actions.pathToSpawn() },
				debugLabel = "Recover->Flee",
			},
			{
				to = "Seek",
				when = Predicates.all({ Predicates.hasTarget(), Predicates.insideChase() }),
				actions = { Actions.clearReturningHome(), Actions.enableRunning(), Actions.pathToTarget() },
				debugLabel = "Recover->Seek",
			},
			{
				to = "Idle",
				when = Predicates.all({ Predicates.timeInStateAtLeast(0.5), Predicates.reachedSpawn() }),
				actions = { Actions.clearReturningHome(), Actions.scheduleIdleHold(), Actions.stopMovement() },
				debugLabel = "Recover->Idle (ReachedSpawn)",
			},
			{
				to = "Idle",
				when = Predicates.timeInStateAtLeast(5.0),
				actions = { Actions.scheduleIdleHold(), Actions.stopMovement() },
				debugLabel = "Recover->Idle (Timeout)",
			},
		},
	}

	states.Dead = {
		onEnter = { Actions.stopMovement(), Actions.clearTarget() },
		transitions = {},
	}

	config.graph = {
		initialState = "Idle",
		states = states,
	}
	config.globalTransitions = globalTransitions

	return config
end

return Defaults
