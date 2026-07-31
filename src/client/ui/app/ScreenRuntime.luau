--!strict
-- Starts the screen-space UI tree. The HUD counterpart to UIRuntime.
--
-- Deliberately thin: everything registered in ScreenRegistry renders into one persistent root, so
-- unlike world panels there are no surfaces to create, place, fade or tear down. Bootstrap calls
-- start/stop and never touches React.

local ScreenRoot = require(script.Parent.ScreenRoot)
local HudRoot = require(script.Parent.HudRoot)

local React = require(game:GetService("ReplicatedStorage").Packages.React)

local ScreenRuntime = {}

local started = false

function ScreenRuntime.start()
	if started then
		return
	end
	started = true
	ScreenRoot.start(React.createElement(HudRoot))
end

function ScreenRuntime.stop()
	if not started then
		return
	end
	started = false
	ScreenRoot.stop()
end

return ScreenRuntime
