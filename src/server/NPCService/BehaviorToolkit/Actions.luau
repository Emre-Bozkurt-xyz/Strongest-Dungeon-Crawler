--!strict
local Actions = {}

local function behaviorCall(methodName: string): ()
	return function(ctx)
		local behavior = ctx.behavior
		local method = behavior[methodName]
		if type(method) == "function" then
			(method :: any)(behavior, ctx)
		end
	end
end

function Actions.stopMovement(): ()
	return behaviorCall("stopMovement")
end

function Actions.enableWalking(): ()
	return behaviorCall("enableWalking")
end

function Actions.enableRunning(): ()
	return behaviorCall("enableRunning")
end

function Actions.startPatrol(): ()
	return behaviorCall("startPatrol")
end

function Actions.continuePatrol(): ()
	return behaviorCall("continuePatrol")
end

function Actions.scheduleIdleHold(): ()
	return behaviorCall("scheduleIdleHold")
end

function Actions.acquireTarget(): ()
	return behaviorCall("acquireTarget")
end

function Actions.clearTarget(): ()
	return behaviorCall("clearTarget")
end

function Actions.attack(): ()
	return behaviorCall("attemptAttack")
end

function Actions.markReturningHome(): ()
	return behaviorCall("markReturningHome")
end

function Actions.clearReturningHome(): ()
	return behaviorCall("clearReturningHome")
end

function Actions.pathToTarget(): ()
	return behaviorCall("pathToTarget")
end

function Actions.pathToSpawn(): ()
	return behaviorCall("pathToSpawn")
end

function Actions.pathHomeIfReturning(): ()
	return behaviorCall("pathHomeIfReturning")
end

return Actions
