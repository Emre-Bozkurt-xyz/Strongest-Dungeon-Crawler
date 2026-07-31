--!strict
-- Container for the item inspect panel: reads which item the menu is inspecting and hands it to
-- ItemCard.
--
-- The split exists so nothing has to *push* an item into the card (R16). The old plugin called
-- `runtime:setInspectState(next.inspect)` every state change; the container just reads it, and the
-- card stays reusable for R14's hover tooltip, which inspects an item the menu knows nothing about.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
-- `script` here IS the ItemInspectPanel module (init.luau collapses into its folder), so Parent is
-- `panels` and Parent.Parent is `ui`. ItemCard, being a child, needs one more level than this.
local useMenuState = require(script.Parent.Parent.hooks.useMenuState)
local ItemCard = require(script.ItemCard)

local function ItemInspectPanel()
	local state = useMenuState()

	local inspect = state and state.inspect
	local payload = inspect and inspect.payload
	local uid = if type(payload) == "table" and type(payload.uid) == "string" then payload.uid else nil

	return React.createElement(ItemCard, { uid = uid })
end

return ItemInspectPanel
