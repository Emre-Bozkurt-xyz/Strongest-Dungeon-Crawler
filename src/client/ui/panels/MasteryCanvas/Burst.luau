--!strict
-- A small burst of light when the player takes an action in the mind-space: motes fly out from a
-- point, slow as if through water, and fade (docs/planning/mastery-mind-space.md, "Interaction").
--
-- Each burst runs on its own clock for LIFETIME and then asks to be removed.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local React = require(ReplicatedStorage.Packages.React)

local e = React.createElement

local LIFETIME = 0.9
-- How fast the motes lose speed: higher stops them sooner.
local DRAG = 4.5

export type Props = {
	-- Where it bursts from, in its parent's pixels.
	position: Vector2,
	-- Bigger for bigger moments (attuning a mastery).
	strength: number?,
	color: Color3?,
	-- Seeds the spread, so two bursts at one place do not look identical.
	seed: number,
	onDone: () -> (),
}

type Mote = { direction: Vector2, speed: number, size: number }

local function Burst(props: Props)
	local strength = props.strength or 1
	local age, setAge = React.useBinding(0)
	local motes = React.useMemo(function(): { Mote }
		local random = Random.new(props.seed)
		local out: { Mote } = {}
		for _ = 1, math.floor(18 * strength + 0.5) do
			local angle = random:NextNumber(0, math.pi * 2)
			table.insert(out, {
				direction = Vector2.new(math.cos(angle), math.sin(angle)),
				speed = random:NextNumber(220, 420) * math.sqrt(strength),
				size = if random:NextNumber() < 0.3 then 5 else 3,
			})
		end
		return out
	end, {})

	React.useEffect(function()
		local elapsed = 0
		local connection
		connection = RunService.Heartbeat:Connect(function(dt)
			elapsed += dt
			setAge(elapsed)
			if elapsed >= LIFETIME then
				connection:Disconnect()
				props.onDone()
			end
		end)
		return function()
			connection:Disconnect()
		end
	end, {})

	local children: { [string]: any } = {
		-- A ring that swells once, under the motes.
		Ring = e("Frame", {
			Size = age:map(function(t: number)
				local d = 40 + 160 * strength * (1 - math.exp(-DRAG * t))
				return UDim2.fromOffset(d, d)
			end),
			Position = UDim2.fromOffset(props.position.X, props.position.Y),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			ZIndex = 8,
		}, {
			Round = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
			Stroke = e("UIStroke", {
				Color = props.color or Color3.new(1, 1, 1),
				Thickness = 1,
				Transparency = age:map(function(t: number)
					return math.clamp(0.3 + t / (LIFETIME * 0.6), 0, 1)
				end),
			}),
		}),
	}
	for index, mote in ipairs(motes) do
		children[`Mote{index}`] = e("Frame", {
			Size = UDim2.fromOffset(mote.size, mote.size),
			Position = age:map(function(t: number)
				-- Distance under drag: speed * (1 - e^(-k t)) / k.
				local travelled = mote.speed * (1 - math.exp(-DRAG * t)) / DRAG
				local at = props.position + mote.direction * travelled
				return UDim2.fromOffset(at.X, at.Y)
			end),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = props.color or Color3.new(1, 1, 1),
			BackgroundTransparency = age:map(function(t: number)
				return math.clamp(t / LIFETIME, 0, 1) ^ 0.7
			end),
			BorderSizePixel = 0,
			ZIndex = 8,
		}, {
			Round = e("UICorner", { CornerRadius = UDim.new(1, 0) }),
		})
	end
	return e(React.Fragment, nil, children)
end

return Burst
