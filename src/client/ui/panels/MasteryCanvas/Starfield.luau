--!strict
-- The mind-space's sky: faint points of light scattered over the black, each blinking slowly on its
-- own rhythm. Seeded, so the sky is the same every time it opens.
--
-- One clock binding drives every star, and it only runs while the sky is shown.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local React = require(ReplicatedStorage.Packages.React)

local e = React.createElement

local COUNT = 150
local SEED = 7

type Star = { x: number, y: number, size: number, base: number, depth: number, speed: number, phase: number }

local stars: { Star } = {}
do
	local random = Random.new(SEED)
	for _ = 1, COUNT do
		table.insert(stars, {
			x = random:NextNumber(),
			y = random:NextNumber(),
			size = if random:NextNumber() < 0.12 then 3 else if random:NextNumber() < 0.5 then 2 else 1,
			-- Opacity at its brightest, and how far it fades from that.
			base = random:NextNumber(0.25, 0.85),
			depth = random:NextNumber(0.3, 1),
			speed = random:NextNumber(0.4, 1.3),
			phase = random:NextNumber(0, math.pi * 2),
		})
	end
end

export type Props = {
	active: boolean,
	-- 0..1 binding: how present the sky is.
	presence: any,
	zIndex: number?,
}

local function Starfield(props: Props)
	local clock, setClock = React.useBinding(0)
	React.useEffect(function()
		if not props.active then
			return
		end
		local elapsed = 0
		local connection = RunService.Heartbeat:Connect(function(dt)
			elapsed += dt
			setClock(elapsed)
		end)
		return function()
			connection:Disconnect()
		end
	end, { props.active })

	local children: { [string]: any } = {}
	for index, star in ipairs(stars) do
		children[`Star{index}`] = e("Frame", {
			Size = UDim2.fromOffset(star.size, star.size),
			Position = UDim2.fromScale(star.x, star.y),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			BackgroundTransparency = React.joinBindings({ clock = clock, presence = props.presence }):map(
				function(values: { clock: number, presence: number })
					local blink = 0.5 + 0.5 * math.sin(values.clock * star.speed + star.phase)
					local opacity = star.base * (1 - star.depth * blink) * values.presence
					return 1 - opacity
				end
			),
		}, {
			Round = if star.size > 1 then e("UICorner", { CornerRadius = UDim.new(1, 0) }) else nil,
		})
	end

	return e("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = props.zIndex,
	}, children)
end

return Starfield
