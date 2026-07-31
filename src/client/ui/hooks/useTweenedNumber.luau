--!strict
-- A number that eases toward its latest target instead of jumping, for gauges that used to be driven
-- by a hand-written TweenService call (HealthBarController, ManaBarController, StaminaBarController).
--
-- Returns a binding, not state (R6: refs + TweenService, no motion library). Gauge and RadialGauge
-- both accept a binding in place of a plain number and write it straight to the property they
-- animate, so this drives them without re-rendering the panel every frame the value is moving.
--
-- The old stamina controller tweened its two half-discs separately, splitting the 0.3s duration
-- between them by how much of the 360 degrees each side had left to cover -- a workaround for handing
-- off two independent per-side tweens at the 180 degree seam without a visible speed jump. That
-- workaround is unnecessary here: RadialGauge derives both halves from one binding every frame, so
-- easing that single source value keeps both halves in lockstep for free.

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local DEFAULT_DURATION = 0.3
local DEFAULT_EASING_STYLE = Enum.EasingStyle.Quad
local DEFAULT_EASING_DIRECTION = Enum.EasingDirection.Out

type Sweep = {
	from: number,
	to: number,
	startedAt: number,
}

local function useTweenedNumber(
	target: number,
	duration: number?,
	easingStyle: Enum.EasingStyle?,
	easingDirection: Enum.EasingDirection?
)
	local value, setValue = React.useBinding(target)
	local sweep = React.useRef({ from = target, to = target, startedAt = os.clock() } :: Sweep)

	React.useEffect(function()
		local current = sweep.current
		if current.to ~= target then
			current.from = value:getValue()
			current.to = target
			current.startedAt = os.clock()
		end
	end, { target })

	React.useEffect(function()
		local dur = duration or DEFAULT_DURATION
		local style = easingStyle or DEFAULT_EASING_STYLE
		local direction = easingDirection or DEFAULT_EASING_DIRECTION

		local connection = RunService.Heartbeat:Connect(function()
			local current = sweep.current
			if current.from == current.to then
				return
			end
			local alpha = if dur <= 0 then 1 else math.clamp((os.clock() - current.startedAt) / dur, 0, 1)
			local eased = TweenService:GetValue(alpha, style, direction)
			setValue(current.from + (current.to - current.from) * eased)
			if alpha >= 1 then
				current.from = current.to
			end
		end)

		return function()
			connection:Disconnect()
		end
	end, {})

	return value
end

return useTweenedNumber
