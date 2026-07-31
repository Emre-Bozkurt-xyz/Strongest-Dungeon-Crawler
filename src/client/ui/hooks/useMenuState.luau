--!strict
-- Menu state, read through MenuOrchestrator, which owns the MenuStateStore instance.
--
-- Going through the orchestrator rather than the store keeps the store's lifetime (created on start,
-- dropped on stop) out of the component's concern.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local MenuOrchestrator = require(script.Parent.Parent.menu.MenuOrchestrator)

local function useMenuState(): any
	local state, setState = React.useState(function()
		return MenuOrchestrator.getState()
	end)

	React.useEffect(function()
		local disconnect = MenuOrchestrator.onChanged(function(_prev, next)
			setState(next)
		end)
		setState(MenuOrchestrator.getState())
		return disconnect
	end, {})

	return state
end

return useMenuState
