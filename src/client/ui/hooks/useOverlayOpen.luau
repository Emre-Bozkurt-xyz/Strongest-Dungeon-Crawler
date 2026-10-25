--!strict
-- Whether a full-screen overlay (the mastery canvas) is open, for HUD elements that step aside
-- under one.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local InteractionStateController = require(script.Parent.Parent.Parent.input.InteractionStateController)

local function useOverlayOpen(): boolean
	local open, setOpen = React.useState(function()
		return InteractionStateController.getState().overlayOpen
	end)

	React.useEffect(function()
		local disconnect = InteractionStateController.onChanged(function(_previous, nextState)
			setOpen(nextState.overlayOpen)
		end)
		setOpen(InteractionStateController.getState().overlayOpen)
		return disconnect
	end, {})

	return open
end

return useOverlayOpen
