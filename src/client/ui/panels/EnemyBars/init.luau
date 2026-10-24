--!strict
-- Health bars over revealed enemies: name, a segmented bar in the danger colour that leaves a trail of
-- the cells a hit took, and the exact health or, when only that is revealed, a percentage.
--
-- Screen UI placed over each enemy's projected position, like the loot plates and the vitals: one
-- size at any distance, drawn over effects. The nearest few stay at full strength and the rest step
-- down, so a crowd stays readable. Hidden while a menu is open.
--
-- `script` here IS the EnemyBars module (init.luau collapses into its folder), so Parent is `panels`
-- and Parent.Parent is `ui`.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local React = require(ReplicatedStorage.Packages.React)

local EnemyHealthClient = require(script.Parent.Parent.controllers.EnemyHealthClient)
local SegmentedGauge = require(script.Parent.Parent.components.SegmentedGauge)
local ThemeContext = require(script.Parent.Parent.hooks.ThemeContext)
local useMenuState = require(script.Parent.Parent.hooks.useMenuState)

local e = React.createElement

-- Studs above the enemy's root.
local HEIGHT = 3.0
-- Pixels. Sized for a glance at a moving target: the name and health have to read at once over any
-- background, so they are a step larger and heavier than panel text, with a solid outline.
local SIZE = Vector2.new(176, 36)
-- Bars past this many, nearest first, step down in strength.
local FULL_COUNT = 6
local MIN_STRENGTH = 0.3
-- Alpha per second: a bar cuts in or out in about a tenth of a second.
local ALPHA_RATE = 10

type Placement = { position: Vector2, alpha: number }

local function useEnemyHealth(): { EnemyHealthClient.Entry }
	local entries, setEntries = React.useState(EnemyHealthClient.getSnapshot)
	React.useEffect(function()
		local disconnect = EnemyHealthClient.onChanged(function()
			setEntries(EnemyHealthClient.getSnapshot())
		end)
		setEntries(EnemyHealthClient.getSnapshot())
		return disconnect
	end, {})
	return entries
end

local function EnemyBar(props: { entry: EnemyHealthClient.Entry, placement: any })
	local theme = ThemeContext.useTheme()
	local entry = props.entry
	local value = if entry.current and entry.max
		then `{math.floor(entry.current)}/{math.floor(entry.max)}`
		else `{math.floor(entry.ratio * 100 + 0.5)}%`

	return e("CanvasGroup", {
		Size = UDim2.fromOffset(SIZE.X, SIZE.Y),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = props.placement:map(function(p: Placement?)
			return if p then UDim2.fromOffset(p.position.X, p.position.Y) else UDim2.new()
		end),
		GroupTransparency = props.placement:map(function(p: Placement?)
			return if p then 1 - p.alpha else 1
		end),
		Visible = props.placement:map(function(p: Placement?)
			return p ~= nil and p.alpha > 0.01
		end),
		BackgroundTransparency = 1,
	}, {
		Name = e("TextLabel", {
			Text = entry.name,
			Size = UDim2.new(1, -70, 0, 20),
			BackgroundTransparency = 1,
			FontFace = theme.face.bodyBold,
			TextSize = theme.type.title,
			TextColor3 = theme.color.textHeading,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd,
		}, {
			Outline = e("UIStroke", { Color = theme.color.surface, Thickness = 2, Transparency = 0 }),
		}),
		Value = e("TextLabel", {
			Text = value,
			Size = UDim2.new(0, 70, 0, 20),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			BackgroundTransparency = 1,
			FontFace = Font.new(theme.face.mono.Family, Enum.FontWeight.Bold),
			TextSize = theme.type.body,
			TextColor3 = theme.color.textPrimary,
			TextXAlignment = Enum.TextXAlignment.Right,
		}, {
			Outline = e("UIStroke", { Color = theme.color.surface, Thickness = 2, Transparency = 0 }),
		}),
		Gauge = e(SegmentedGauge, {
			value = entry.ratio,
			color = theme.color.danger,
			segments = 16,
			trail = true,
			size = UDim2.new(1, 0, 0, 7),
			position = UDim2.new(0, 0, 1, -8),
		}),
	})
end

local function EnemyBars()
	local entries = useEnemyHealth()
	local menu = useMenuState()
	local shown = not menu.modal.open

	local layout, setLayout = React.useBinding({} :: { [string]: Placement })
	local current = React.useRef(entries)
	current.current = entries
	local visible = React.useRef(shown)
	visible.current = shown

	React.useEffect(function()
		local alphas: { [string]: number } = {}
		-- Where each bar last stood, so one losing its enemy fades out in place rather than vanishing.
		local lastScreen: { [string]: Vector2 } = {}
		local name = `EnemyBars_{HttpService:GenerateGUID(false)}`
		RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 1, function(dt: number)
			local camera = workspace.CurrentCamera
			if not camera then
				return
			end
			local viewport = camera.ViewportSize

			-- Projected positions, and distance order for stepping down the far ones.
			local candidates: { { id: string, screen: Vector2, distance: number } } = {}
			local targets: { [string]: number } = {}
			for _, entry in ipairs(current.current :: { EnemyHealthClient.Entry }) do
				local anchor = entry.anchor
				targets[entry.id] = 0
				if anchor and anchor.Parent and entry.present and visible.current then
					local world = anchor.Position + Vector3.new(0, HEIGHT, 0)
					local point = camera:WorldToViewportPoint(world)
					local onScreen = point.Z > 0
						and point.X > -SIZE.X
						and point.X < viewport.X + SIZE.X
						and point.Y > -SIZE.Y
						and point.Y < viewport.Y + SIZE.Y
					if onScreen then
						table.insert(candidates, {
							id = entry.id,
							screen = Vector2.new(math.round(point.X), math.round(point.Y)),
							distance = (camera.CFrame.Position - world).Magnitude,
						})
					end
				end
			end
			table.sort(candidates, function(a, b)
				return a.distance < b.distance
			end)

			local out: { [string]: Placement } = {}
			for rank, candidate in ipairs(candidates) do
				local over = rank - FULL_COUNT
				targets[candidate.id] = if over > 0 then math.max(MIN_STRENGTH, 1 - over * 0.1) else 1
				out[candidate.id] = { position = candidate.screen, alpha = 0 }
				lastScreen[candidate.id] = candidate.screen
			end

			for id, target in pairs(targets) do
				local alpha = alphas[id] or 0
				local step = ALPHA_RATE * dt
				alpha = if alpha < target then math.min(target, alpha + step) else math.max(target, alpha - step)
				alphas[id] = alpha
				local placed = out[id]
				if placed then
					placed.alpha = alpha
				elseif alpha > 0 and lastScreen[id] then
					out[id] = { position = lastScreen[id], alpha = alpha }
				end
			end
			for id in pairs(alphas) do
				if targets[id] == nil then
					alphas[id] = nil
					lastScreen[id] = nil
				end
			end
			setLayout(out)
		end)
		return function()
			RunService:UnbindFromRenderStep(name)
		end
	end, {})

	local bars: { [string]: any } = {}
	for _, entry in ipairs(entries) do
		bars[entry.id] = e(EnemyBar, {
			entry = entry,
			placement = layout:map(function(all: { [string]: Placement })
				return all[entry.id]
			end),
		})
	end
	return e(React.Fragment, nil, bars)
end

return EnemyBars
