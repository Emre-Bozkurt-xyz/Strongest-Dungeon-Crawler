--!strict
-- The always-on vitals: a small readout beside the character and the low-HP edge pulse.
--
-- Shown only while it has something to say. It fades in when any vital drops below full and out a
-- little after everything is full again, so an idle screen stays empty. It also yields to the menu,
-- whose System view shows the same vitals in full.
--
-- `script` here IS the VitalsHud module (init.luau collapses into its folder), so Parent is `panels`
-- and Parent.Parent is `ui`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local DevTuningService = require(script.Parent.Parent.Parent.dev.DevTuningService)
local ThemeContext = require(script.Parent.Parent.hooks.ThemeContext)
local useMenuState = require(script.Parent.Parent.hooks.useMenuState)
local useSpring = require(script.Parent.Parent.hooks.useSpring)
local useStats = require(script.Parent.Parent.hooks.useStats)
local Selector = require(script.Parent.Parent.selectors.systemStatus)

local LowHealthVignette = require(script.LowHealthVignette)
local VitalsReadout = require(script.VitalsReadout)
local useVitalsAnchor = require(script.useVitalsAnchor)

local e = React.createElement

-- Ratios at or above this count as full; regen lands on max, but float maths may not.
local FULL = 0.999

local function findVital(vitals: { Selector.VitalView }, label: string): Selector.VitalView?
	for _, vital in ipairs(vitals) do
		if vital.label == label then
			return vital
		end
	end
	return nil
end

local function VitalsHud()
	local theme = ThemeContext.useTheme()
	local menu = useMenuState()
	local vitals = Selector.buildVitals(useStats())

	local health = findVital(vitals, "HP")
	local mana = findVital(vitals, "MP")
	local stamina = findVital(vitals, "Stamina")

	local depleted = false
	for _, vital in ipairs(vitals) do
		if vital.ratio < FULL then
			depleted = true
		end
	end

	local awake, setAwake = React.useState(depleted)
	React.useEffect(function()
		if depleted then
			setAwake(true)
			return
		end
		local linger = task.delay(DevTuningService.get("VitalsHud.lingerSeconds"), setAwake, false)
		return function()
			task.cancel(linger)
		end
	end, { depleted })

	local shown = awake and not menu.modal.open
	local opacity = useSpring(if shown then 1 else 0, theme.motion.settle)
	local position = useVitalsAnchor(VitalsReadout.SIZE)

	return e(React.Fragment, nil, {
		Vignette = e(LowHealthVignette, { ratio = if health then health.ratio else 1 }),
		Readout = e("CanvasGroup", {
			Size = UDim2.fromOffset(VitalsReadout.SIZE.X, VitalsReadout.SIZE.Y),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = position,
			BackgroundTransparency = 1,
			GroupTransparency = opacity:map(function(v: number)
				return 1 - v
			end),
			Visible = opacity:map(function(v: number)
				return v > 0.005
			end),
		}, {
			View = e(VitalsReadout.render, { health = health, mana = mana, stamina = stamina }),
		}),
	})
end

return VitalsHud
