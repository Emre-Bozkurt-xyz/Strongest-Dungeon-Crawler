--!strict

local WorldPanelRegistry = {}
WorldPanelRegistry.__index = WorldPanelRegistry

function WorldPanelRegistry.new()
	local self = setmetatable({}, WorldPanelRegistry)
	self.panels = {} :: { [string]: any }
	self.groups = {} :: { [string]: { [string]: any } }
	self.frozen = {} :: { [string]: boolean }
	self.visibilityOps = {} :: { [string]: number }
	self.visibilitySeq = 0
	self.activeTweens = {} :: { [Instance]: Tween }
	return self
end

return WorldPanelRegistry