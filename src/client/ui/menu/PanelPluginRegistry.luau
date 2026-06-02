--!strict

local Types = require(script.Parent.PanelPluginTypes)

type PanelPlugin = Types.PanelPlugin
type PanelPluginHost = Types.PanelPluginHost
type MenuState = Types.MenuState

local PanelPluginRegistry = {}
PanelPluginRegistry.__index = PanelPluginRegistry

function PanelPluginRegistry.new()
	local self = setmetatable({}, PanelPluginRegistry)
	self._byId = {} :: { [string]: PanelPlugin }
	self._ordered = {} :: { PanelPlugin }
	self._host = nil :: PanelPluginHost?
	return self
end

function PanelPluginRegistry:register(plugin: PanelPlugin)
	if self._byId[plugin.id] then
		error(`PanelPluginRegistry: duplicate plugin id '{plugin.id}'`)
	end
	self._byId[plugin.id] = plugin
	table.insert(self._ordered, plugin)
	if self._host then
		plugin.mount(self._host)
	end
end

function PanelPluginRegistry:mountAll(host: PanelPluginHost)
	self._host = host
	for _, plugin in ipairs(self._ordered) do
		plugin.mount(host)
	end
end

function PanelPluginRegistry:onStateChanged(prev: MenuState, next: MenuState)
	for _, plugin in ipairs(self._ordered) do
		plugin.onStateChanged(prev, next)
	end
end

function PanelPluginRegistry:broadcast(event: any)
	for _, plugin in ipairs(self._ordered) do
		plugin.onData(event)
	end
end

function PanelPluginRegistry:unmountAll()
	for _, plugin in ipairs(self._ordered) do
		plugin.unmount()
	end
	self._host = nil
end

return PanelPluginRegistry