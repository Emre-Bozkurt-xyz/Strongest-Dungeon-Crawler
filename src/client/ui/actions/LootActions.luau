--!strict
-- Pointer intents from the nearby-loot panel.
--
-- Both route through LootClient rather than straight to the server: selection is client-only state
-- it owns, and pickup has to share its throttle and interaction gate with the keyboard path, which
-- LootClient also owns. The request itself is built in ItemActions.pickup.

local LootClient = require(script.Parent.Parent.controllers.LootClient)

local LootActions = {}

function LootActions.select(uid: string)
	LootClient.selectFromPanel(uid)
end

function LootActions.pickup(uid: string)
	LootClient.pickupFromPanel(uid)
end

return LootActions
