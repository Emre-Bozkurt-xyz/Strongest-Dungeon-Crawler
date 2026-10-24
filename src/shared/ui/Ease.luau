--!strict
-- Easing curves for fixed-duration motion, t in 0..1.
--
-- The UI's transitions are deliberately not springs: a spring's long settling tail is what reads as
-- floaty. These arrive in a fixed time and stop dead -- out-curves decelerate hard into place, in-curves
-- accelerate away, which is how things leave.

local Ease = {}

-- Most of the move happens at once, then it brakes hard onto the target.
function Ease.expoOut(t: number): number
	if t >= 1 then
		return 1
	end
	return 1 - 2 ^ (-10 * t)
end

function Ease.quartOut(t: number): number
	local inv = 1 - t
	return 1 - inv * inv * inv * inv
end

-- Starts slow and snaps shut: for collapses and exits.
function Ease.quartIn(t: number): number
	return t * t * t * t
end

function Ease.clamp01(t: number): number
	return math.clamp(t, 0, 1)
end

return Ease
