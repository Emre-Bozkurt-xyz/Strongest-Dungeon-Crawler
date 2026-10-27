--!strict
-- The player's progression (character XP, mastery, form selections), read from ProgressionClient.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ProgressionClient = require(script.Parent.Parent.Parent.Progression.ProgressionClient)

local function useProgression(): ProgressionClient.Snapshot?
	local data, setData = React.useState(ProgressionClient.get())

	React.useEffect(function()
		local disconnect = ProgressionClient.onChanged(function()
			setData(ProgressionClient.get())
		end)
		setData(ProgressionClient.get())
		return disconnect
	end, {})

	return data
end

return useProgression
