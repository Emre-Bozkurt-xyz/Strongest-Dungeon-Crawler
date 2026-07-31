--!strict
-- Current combat loadout snapshot.
--
-- Reads from InventoryClient rather than CombatLoadoutMirror: the mirror is a downstream cache that
-- InventoryClient writes before it notifies, so subscribing to the mirror would mean a second
-- notification path for data that already has one, with the drift that invites.
--
-- The mirror still exists for synchronous reads from skill code, which needs a value without a
-- dependency on InventoryClient. It is not a second source of truth.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local InventoryClient = require(script.Parent.Parent.Parent.Inventory.InventoryClient)
local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)

local function useCombatLoadout(): ItemTypes.CombatLoadoutSnapshot?
	local loadout, setLoadout = React.useState(InventoryClient.getCombatLoadout())

	React.useEffect(function()
		local disconnect = InventoryClient.onChanged(function(context)
			-- Only loadout changes matter here; re-reading on every inventory delta would re-render
			-- every consumer whenever a stack size changed.
			if context.kind == "loadout" or context.kind == "snapshot" then
				setLoadout(InventoryClient.getCombatLoadout())
			end
		end)
		setLoadout(InventoryClient.getCombatLoadout())
		return disconnect
	end, {})

	return loadout
end

return useCombatLoadout
