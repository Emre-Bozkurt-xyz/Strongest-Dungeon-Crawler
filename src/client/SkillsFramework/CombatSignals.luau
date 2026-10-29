--!strict
-- CombatSignals: moments in the player's own combat that the HUD shows, raised by the skills that
-- cause them without those skills knowing about the HUD -- an action refused, a shot leaving, and a
-- charge filling.

export type Cast = {
	startedAt: number,
	-- Seconds to a full charge.
	duration: number,
	-- How a charge that gathers whole things (mana balls) is counted, gathering evenly over the
	-- duration; nil for a smooth charge such as a draw.
	charges: number?,
	-- The resource the charge is made of, which tints what it gathers.
	resource: string?,
}

export type CastShape = {
	charges: number?,
	resource: string?,
}

local CombatSignals = {}

local rejectedListeners: { [{}]: (reason: string) -> () } = {}
local firedListeners: { [{}]: () -> () } = {}
local cast: Cast? = nil

function CombatSignals.rejected(reason: string)
	for _, listener in pairs(rejectedListeners) do
		task.spawn(listener, reason)
	end
end

function CombatSignals.onRejected(callback: (reason: string) -> ()): () -> ()
	local key = {}
	rejectedListeners[key] = callback
	return function()
		rejectedListeners[key] = nil
	end
end

-- A shot left the player's weapon.
function CombatSignals.fired()
	for _, listener in pairs(firedListeners) do
		task.spawn(listener)
	end
end

function CombatSignals.onFired(callback: () -> ()): () -> ()
	local key = {}
	firedListeners[key] = callback
	return function()
		firedListeners[key] = nil
	end
end

-- A held skill started charging toward a full charge in `duration` seconds.
function CombatSignals.beginCast(duration: number, shape: CastShape?)
	cast = {
		startedAt = os.clock(),
		duration = duration,
		charges = shape and shape.charges,
		resource = shape and shape.resource,
	}
end

function CombatSignals.endCast()
	cast = nil
end

-- The charge in progress, read per frame by whatever draws it.
function CombatSignals.getCast(): Cast?
	return cast
end

return CombatSignals
