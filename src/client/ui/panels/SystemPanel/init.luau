--!strict
-- Container for the system panel: reads player stats and attributes and hands a derived view model
-- to StatusView.
--
-- Nothing pushes this data in (R16) -- the old runtime subscribed StatsClient/AttributesClient itself
-- and walked bound nodes to write values in; this just reads both stores through hooks and rebuilds
-- the view model on every change.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
-- `script` here IS the SystemPanel module (init.luau collapses into its folder), so Parent is
-- `panels` and Parent.Parent is `ui`. StatusView, being a child, needs one more level than this.
local useStats = require(script.Parent.Parent.hooks.useStats)
local useAttributes = require(script.Parent.Parent.hooks.useAttributes)
local AttributeActions = require(script.Parent.Parent.actions.AttributeActions)
local Selector = require(script.Parent.Parent.selectors.systemStatus)
local StatusView = require(script.StatusView)

local function SystemPanel()
	local stats = useStats()
	local attributes = useAttributes()
	local view = Selector.buildView(stats, attributes)

	return React.createElement(StatusView, {
		view = view,
		onSpend = AttributeActions.spendPoint,
	})
end

return SystemPanel
