--!strict
-- Inventory state, read from InventoryClient.
--
-- One hook per store rather than a generic `useStore` (R4): the stores differ in call style and
-- callback signature, so a generic hook would need a per-store adapter anyway. This keeps each
-- store's shape in one place and hands components a plain typed value.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local InventoryClient = require(script.Parent.Parent.Parent.Inventory.InventoryClient)
local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)

export type InventoryView = {
	inventory: ItemTypes.InventoryState?,
	equipment: ItemTypes.EquipmentState?,
	items: { [string]: ItemTypes.ItemInstance },
}

local function read(): InventoryView
	return {
		inventory = InventoryClient.getInventory(),
		equipment = InventoryClient.getEquipment(),
		items = InventoryClient.getItems(),
	}
end

local function useInventory(): InventoryView
	local view, setView = React.useState(read)

	React.useEffect(function()
		-- Re-read on every change rather than diffing here: InventoryClient already owns what
		-- changed, and a component that cares can memo on the field it uses.
		--
		-- The returned unsubscribe is the effect cleanup. Without it the callback outlives the
		-- component, sets state on an unmounted tree, and leaks a closure per mount.
		local disconnect = InventoryClient.onChanged(function()
			setView(read())
		end)
		-- Between first render and this effect running, a snapshot may already have landed.
		setView(read())
		return disconnect
	end, {})

	return view
end

return useInventory
