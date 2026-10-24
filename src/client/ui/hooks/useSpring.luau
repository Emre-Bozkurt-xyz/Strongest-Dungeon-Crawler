--!strict
-- A number that springs toward `target`, as a React binding.
--
-- A binding writes the property it is bound to directly, so an animating value never re-renders the
-- component -- dozens of slots can hover-animate at once without reconciling anything. Pass a preset
-- from the theme (`theme.motion.snap` and so on) so the feel of the UI is tuned in one place.
--
-- Retargeting mid-move keeps the current velocity, which is what makes a spring read as one motion
-- rather than a tween that restarts. The Heartbeat connection only exists while moving; at rest the
-- hook costs nothing per frame.
--
-- `from` starts the spring somewhere other than its target, for an entrance on mount.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local React = require(ReplicatedStorage.Packages.React)
local Themes = require(ReplicatedStorage.Shared.ui.themes)

type State = {
	position: number,
	velocity: number,
	target: number,
	spec: Themes.SpringSpec,
	connection: RBXScriptConnection?,
}

-- Fixed substep keeps semi-implicit Euler stable at any frame rate, including a long first frame.
local SUBSTEP = 1 / 240
local REST_EPSILON = 1e-3
local DEFAULT_SPEC: Themes.SpringSpec = { frequency = 4, damping = 1 }

local function atRest(state: State): boolean
	return math.abs(state.position - state.target) < REST_EPSILON and math.abs(state.velocity) < REST_EPSILON
end

local function step(state: State, dt: number)
	local omega = 2 * math.pi * state.spec.frequency
	local remaining = dt
	while remaining > 0 do
		local h = math.min(SUBSTEP, remaining)
		local accel = omega * omega * (state.target - state.position) - 2 * state.spec.damping * omega * state.velocity
		state.velocity += accel * h
		state.position += state.velocity * h
		remaining -= h
	end
end

local function useSpring(
	target: number,
	spec: Themes.SpringSpec?,
	from: number?
): (React.Binding<number>, (value: number) -> ())
	local initial = if from ~= nil then from else target
	local binding, setBinding = React.useBinding(initial)
	local stateRef = React.useRef(nil :: State?)
	if stateRef.current == nil then
		stateRef.current = {
			position = initial,
			velocity = 0,
			target = target,
			spec = spec or DEFAULT_SPEC,
			connection = nil,
		}
	end
	local state = stateRef.current :: State
	state.target = target
	state.spec = spec or state.spec

	local function run()
		if state.connection or atRest(state) then
			return
		end
		state.connection = RunService.Heartbeat:Connect(function(dt: number)
			step(state, dt)
			if atRest(state) then
				state.position = state.target
				state.velocity = 0
				local connection = state.connection
				state.connection = nil
				if connection then
					connection:Disconnect()
				end
			end
			setBinding(state.position)
		end)
	end

	React.useEffect(run, { target })

	React.useEffect(function()
		return function()
			if state.connection then
				state.connection:Disconnect()
				state.connection = nil
			end
		end
	end, {})

	-- Jumps to a value with no motion, then springs on to the target from there -- e.g. to replay an
	-- entrance on a component that is already mounted.
	local function snapTo(value: number)
		state.position = value
		state.velocity = 0
		setBinding(value)
		run()
	end

	return binding, snapTo
end

return useSpring
