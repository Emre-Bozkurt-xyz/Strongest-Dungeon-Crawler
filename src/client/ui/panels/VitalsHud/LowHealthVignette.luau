--!strict
-- The screen edges pulse red while HP is low.
--
-- The one warning that must not depend on where the player is looking: the readout can be faded,
-- offscreen-clamped or buried under effects, but the edges of the screen are always in peripheral
-- vision. It deepens as HP falls further under the threshold.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local React = require(ReplicatedStorage.Packages.React)

local DevTuningService = require(script.Parent.Parent.Parent.Parent.dev.DevTuningService)
local ThemeContext = require(script.Parent.Parent.Parent.hooks.ThemeContext)
local useSpring = require(script.Parent.Parent.Parent.hooks.useSpring)

local e = React.createElement

export type Props = {
	-- Current HP over max.
	ratio: number,
}

-- How far each edge's glow reaches in, as a fraction of the screen.
local DEPTH = 0.14

-- Gradient rotations that put the opaque end at each edge.
local EDGES = {
	Top = { size = UDim2.fromScale(1, DEPTH), position = UDim2.fromScale(0, 0), anchor = Vector2.new(0, 0), rotation = 90 },
	Bottom = { size = UDim2.fromScale(1, DEPTH), position = UDim2.fromScale(0, 1), anchor = Vector2.new(0, 1), rotation = -90 },
	Left = { size = UDim2.fromScale(DEPTH, 1), position = UDim2.fromScale(0, 0), anchor = Vector2.new(0, 0), rotation = 0 },
	Right = { size = UDim2.fromScale(DEPTH, 1), position = UDim2.fromScale(1, 0), anchor = Vector2.new(1, 0), rotation = 180 },
}

local function LowHealthVignette(props: Props)
	local theme = ThemeContext.useTheme()
	local tuning = DevTuningService.get("VitalsHud.lowHealth")

	local severity = if props.ratio > 0 and props.ratio < tuning.threshold
		then 1 - props.ratio / tuning.threshold
		else 0
	-- Starts clearly visible at the threshold rather than fading up from nothing, since crossing it
	-- is the news.
	local strength = useSpring(if severity > 0 then 0.35 + 0.65 * severity else 0, theme.motion.settle)
	local pulse, setPulse = React.useBinding(0)
	local active = severity > 0

	-- Only ticks while low, so the vignette costs nothing the rest of the time.
	React.useEffect(function()
		if not active then
			return
		end
		local start = os.clock()
		local connection = RunService.RenderStepped:Connect(function()
			setPulse(0.5 + 0.5 * math.sin((os.clock() - start) * 2 * math.pi * tuning.pulseHz))
		end)
		return function()
			connection:Disconnect()
		end
	end, { active, tuning.pulseHz })

	local transparency = React.joinBindings({ strength = strength, pulse = pulse }):map(function(v)
		return 1 - v.strength * (0.4 + 0.3 * v.pulse)
	end)

	local children: { [string]: any } = {}
	for name, edge in pairs(EDGES) do
		children[name] = e("Frame", {
			Size = edge.size,
			Position = edge.position,
			AnchorPoint = edge.anchor,
			BackgroundColor3 = theme.color.danger,
			BackgroundTransparency = transparency,
			BorderSizePixel = 0,
		}, {
			Fade = e("UIGradient", {
				Rotation = edge.rotation,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0),
					NumberSequenceKeypoint.new(1, 1),
				}),
			}),
		})
	end

	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = strength:map(function(v: number)
			return v > 0.005
		end),
	}, children)
end

return LowHealthVignette
