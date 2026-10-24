--!strict
-- A bar made of discrete cells, the System's gauge (from the approved style tile): cells read as a
-- readout projected for the player rather than a generic health bar.
--
-- The fill springs to its value, and an optional trail follows on a slower spring, so cells lost to
-- a hit stay lit in white for a moment before going dark. Both are bindings mapped per cell, so the
-- animation never re-renders the gauge.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ThemeContext = require(script.Parent.Parent.hooks.ThemeContext)
local useSpring = require(script.Parent.Parent.hooks.useSpring)

local e = React.createElement

export type Props = {
	-- 0..1.
	value: number,
	color: Color3?,
	segments: number?,
	-- Pixels between cells.
	gap: number?,
	trail: boolean?,
	size: UDim2?,
	position: UDim2?,
	anchorPoint: Vector2?,
	layoutOrder: number?,
}

local DEFAULT_SEGMENTS = 20

-- What a cell shows: lit by the fill, lit only by the trail, or empty.
type CellState = "fill" | "trail" | "empty"

local function cellState(index: number, segments: number, fill: number, trail: number): CellState
	-- A cell lights once the value covers its midpoint, so a full gauge lights every cell and an
	-- empty one none.
	local midpoint = (index - 0.5) / segments
	if fill >= midpoint then
		return "fill"
	elseif trail >= midpoint then
		return "trail"
	end
	return "empty"
end

local function SegmentedGauge(props: Props)
	local theme = ThemeContext.useTheme()
	local segments = props.segments or DEFAULT_SEGMENTS
	local gap = props.gap or 2
	local color = props.color or theme.color.gaugeFill

	local fill = useSpring(props.value, theme.motion.snap)
	-- Always called so the hook order is fixed; only shown when `trail` is set.
	local trail = useSpring(props.value, theme.motion.drift)
	local both = React.joinBindings({ fill = fill, trail = if props.trail then trail else fill })

	local cells: { [string]: any } = {
		Layout = e("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, gap),
		}),
	}
	for i = 1, segments do
		local state = both:map(function(v)
			return cellState(i, segments, v.fill, v.trail)
		end)
		cells[`Cell{i}`] = e("Frame", {
			-- The gaps come out of the cells so the gauge spans exactly its width.
			Size = UDim2.new(1 / segments, -gap * (segments - 1) / segments, 1, 0),
			LayoutOrder = i,
			BackgroundColor3 = state:map(function(s: CellState): Color3
				if s == "fill" then
					return color
				elseif s == "trail" then
					return theme.color.textPrimary
				end
				return theme.color.gaugeTrack
			end),
			BackgroundTransparency = state:map(function(s: CellState): number
				if s == "fill" then
					return 0
				elseif s == "trail" then
					return 0.35
				end
				return 0.15
			end),
			BorderSizePixel = 0,
		})
	end

	return e("Frame", {
		Size = props.size or UDim2.new(1, 0, 0, 6),
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		LayoutOrder = props.layoutOrder,
		BackgroundTransparency = 1,
	}, cells)
end

return SegmentedGauge
