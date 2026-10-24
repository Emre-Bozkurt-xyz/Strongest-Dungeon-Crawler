--!strict
-- Container for the nearby-loot panel: reads LootClient's snapshot and hands a plain view model to
-- LootList, routing row hover and click back through LootActions.
--
-- `script` here IS the WorldLootInspectPanel module (init.luau collapses into its folder), so Parent
-- is `panels` and Parent.Parent is `ui`. LootList, being a child, needs one more level than this.
--
-- Unlike the menu panels this one holds no state of its own: selection is LootClient's, because the
-- keyboard's up/down and E have to agree with whatever the pointer last hovered.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)

local useNearbyLoot = require(script.Parent.Parent.hooks.useNearbyLoot)
local LootActions = require(script.Parent.Parent.actions.LootActions)
local Selector = require(script.Parent.Parent.selectors.lootList)
local LootList = require(script.LootList)

local function WorldLootInspectPanel()
	local snapshot = useNearbyLoot()

	return React.createElement(LootList, {
		view = Selector.buildView(snapshot),
		onRowHovered = LootActions.select,
		onRowActivated = LootActions.pickup,
	})
end

return WorldLootInspectPanel
