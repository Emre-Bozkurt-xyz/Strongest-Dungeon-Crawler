--!strict
-- A pulse, 1 falling to 0, played the moment a cooldown finishes.
--
-- The cooldown arrives as a binding, which does not re-render anything when it changes, so the
-- crossing to zero is watched each frame. The pulse is a fixed-time ease to a hard stop like every
-- other transition, not a spring: it should land once and be over.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local React = require(ReplicatedStorage.Packages.React)
local Ease = require(ReplicatedStorage.Shared.ui.Ease)

-- Seconds.
local DURATION = 0.32

local function useReadyPulse(cooldown: any): any
	local pulse, setPulse = React.useBinding(0)

	React.useEffect(function()
		local wasCooling = cooldown:getValue() > 0
		local started: number? = nil
		local connection = RunService.Heartbeat:Connect(function()
			local cooling = cooldown:getValue() > 0
			if wasCooling and not cooling then
				started = os.clock()
			end
			wasCooling = cooling
			if started then
				local t = Ease.clamp01((os.clock() - (started :: number)) / DURATION)
				setPulse(1 - Ease.quartOut(t))
				if t >= 1 then
					started = nil
				end
			end
		end)
		return function()
			connection:Disconnect()
		end
	end, { cooldown })

	return pulse
end

return useReadyPulse
