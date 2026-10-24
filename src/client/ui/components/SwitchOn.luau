--!strict
-- Screen UI that switches on and off like the world panels (shared/ui/SwitchOn): a line of light
-- draws out, splits, and opens into the surface; closing collapses it back.
--
-- Children lay out in a fixed `size`; the band reveals them in place rather than squashing them.
-- With `collapseSlot`, the slot the surface takes in a list shrinks with the band, so the items around
-- it close up as it closes instead of jumping when it is removed. `onClosed` fires once a close has
-- finished, which is when a list can drop it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local React = require(ReplicatedStorage.Packages.React)
local Curve = require(ReplicatedStorage.Shared.ui.SwitchOn)
local Ease = require(ReplicatedStorage.Shared.ui.Ease)
local ThemeContext = require(script.Parent.Parent.hooks.ThemeContext)

local e = React.createElement

export type Props = {
	visible: boolean,
	-- Pixels.
	size: Vector2,
	collapseSlot: boolean?,
	layoutOrder: number?,
	position: UDim2?,
	anchorPoint: Vector2?,
	onClosed: (() -> ())?,
	children: any?,
}

-- Pixels: the light lines.
local LINE_THICKNESS = 2
local MIN_BAND = 0.02

local function SwitchOn(props: Props)
	local theme = ThemeContext.useTheme()
	local frame, setFrame = React.useBinding(Curve.CLOSED)
	local band = React.useRef(0)
	local onClosed = React.useRef(props.onClosed)
	onClosed.current = props.onClosed

	React.useEffect(function()
		local opening = props.visible
		local from = band.current :: number
		local duration = Curve.duration(opening, from, theme.transitions)
		local started = os.clock()
		local connection: RBXScriptConnection? = nil

		local function step()
			local t = if duration > 0 then Ease.clamp01((os.clock() - started) / duration) else 1
			local current = if t >= 1 and opening then Curve.OPEN else Curve.frame(opening, t, from)
			band.current = current.band
			setFrame(current)
			if t >= 1 then
				if connection then
					connection:Disconnect()
				end
				if not opening and onClosed.current then
					onClosed.current()
				end
			end
		end

		connection = RunService.Heartbeat:Connect(step)
		step()
		return function()
			if connection and connection.Connected then
				connection:Disconnect()
			end
		end
	end, { props.visible })

	local width, height = props.size.X, props.size.Y
	local function edgeLine(edge: number)
		return e("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = frame:map(function(f: Curve.Frame)
				return UDim2.new(0.5, 0, 0.5, edge * math.max(f.band, MIN_BAND) * height / 2)
			end),
			Size = frame:map(function(f: Curve.Frame)
				return UDim2.fromOffset(width * f.lineLength, LINE_THICKNESS)
			end),
			BackgroundColor3 = theme.color.accent,
			BackgroundTransparency = frame:map(function(f: Curve.Frame)
				return f.lineTransparency
			end),
			BorderSizePixel = 0,
			ZIndex = 10,
		})
	end

	return e("Frame", {
		Size = if props.collapseSlot
			then frame:map(function(f: Curve.Frame)
				return UDim2.fromOffset(width, height * f.band)
			end)
			else UDim2.fromOffset(width, height),
		Position = props.position,
		AnchorPoint = props.anchorPoint,
		LayoutOrder = props.layoutOrder,
		BackgroundTransparency = 1,
	}, {
		Surface = e("CanvasGroup", {
			Size = UDim2.fromOffset(width, height),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			BackgroundTransparency = 1,
			GroupTransparency = frame:map(function(f: Curve.Frame)
				return f.transparency
			end),
		}, {
			Band = e("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = frame:map(function(f: Curve.Frame)
					return UDim2.fromScale(1, math.max(f.band, MIN_BAND))
				end),
				BackgroundTransparency = 1,
				ClipsDescendants = true,
			}, {
				Canvas = e("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromOffset(width, height),
					BackgroundTransparency = 1,
				}, props.children),
			}),
		}),
		-- Outside the CanvasGroup, which is still transparent while the line draws out.
		LineTop = edgeLine(-1),
		LineBottom = edgeLine(1),
	})
end

return SwitchOn
