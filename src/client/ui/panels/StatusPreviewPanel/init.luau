--!strict
-- Container for the status preview: reads live vitals and hands them to StatusPreviewView.
--
-- This panel has no attribute or identity block, unlike SystemPanel, so it calls
-- Selector.buildVitals directly rather than the full Selector.buildView -- the same HP/MP/Stamina
-- reading logic, without paying for the attribute/combat-stat work this panel never shows.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
-- `script` here IS the StatusPreviewPanel module (init.luau collapses into its folder), so Parent is
-- `panels` and Parent.Parent is `ui`. StatusPreviewView, being a child, needs one more level than
-- this.
local useStats = require(script.Parent.Parent.hooks.useStats)
local Selector = require(script.Parent.Parent.selectors.systemStatus)
local StatusPreviewView = require(script.StatusPreviewView)

local function StatusPreviewPanel()
	local stats = useStats()
	local vitals = Selector.buildVitals(stats)

	return React.createElement(StatusPreviewView, { vitals = vitals })
end

return StatusPreviewPanel
