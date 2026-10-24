--!strict
-- Nearby loot and the selected row, read from LootClient.
--
-- LootClient publishes a fresh snapshot table only when something the panel draws changes, so
-- plain useState is enough here: a new identity always means a real change, and the scan running
-- every few frames never reaches React unless a row did.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local LootClient = require(script.Parent.Parent.controllers.LootClient)

local function useNearbyLoot(): LootClient.Snapshot
	local snapshot, setSnapshot = React.useState(LootClient.getSnapshot)

	React.useEffect(function()
		local disconnect = LootClient.onChanged(function()
			setSnapshot(LootClient.getSnapshot())
		end)
		-- A scan may have published between first render and this effect running.
		setSnapshot(LootClient.getSnapshot())
		return disconnect
	end, {})

	return snapshot
end

return useNearbyLoot
