--!strict
-- Container for the system panel: reads player stats and attributes, owns which tab is showing, and
-- hands a derived view model to StatusView.
--
-- Nothing pushes this data in (R16) -- this reads both stores through hooks and rebuilds the view
-- model on every change. The tab is presentation-local state, like the equipment panel's selected
-- socket (R4).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
-- `script` here IS the SystemPanel module (init.luau collapses into its folder), so Parent is
-- `panels` and Parent.Parent is `ui`. StatusView, being a child, needs one more level than this.
local useStats = require(script.Parent.Parent.hooks.useStats)
local useAttributes = require(script.Parent.Parent.hooks.useAttributes)
local useProgression = require(script.Parent.Parent.hooks.useProgression)
local AttributeActions = require(script.Parent.Parent.actions.AttributeActions)
local Selector = require(script.Parent.Parent.selectors.systemStatus)
local StatusView = require(script.StatusView)

local function SystemPanel()
	local stats = useStats()
	local attributes = useAttributes()
	local progression = useProgression()
	local view = Selector.buildView(stats, attributes, progression)
	local tab, setTab = React.useState("status" :: StatusView.Tab)

	return React.createElement(StatusView.render, {
		view = view,
		tab = tab,
		onTab = setTab,
		onSpend = AttributeActions.spendPoint,
	})
end

return SystemPanel
