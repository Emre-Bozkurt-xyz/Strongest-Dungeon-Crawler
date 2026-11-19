--!strict
-- The console store's current snapshot, re-rendering when it changes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ConsoleStore = require(script.Parent.ConsoleStore)

local function useConsole(): ConsoleStore.State
	local snapshot, setSnapshot = React.useState(ConsoleStore.get)
	React.useEffect(function()
		local stop = ConsoleStore.subscribe(function()
			setSnapshot(ConsoleStore.get())
		end)
		setSnapshot(ConsoleStore.get())
		return stop
	end, {})
	return snapshot
end

return useConsole
