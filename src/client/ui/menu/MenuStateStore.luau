--!strict

local MenuReducer = require(script.Parent.MenuReducer)
local Types = require(script.Parent.PanelPluginTypes)

type MenuState = Types.MenuState
type MenuAction = Types.MenuAction

local MenuStateStore = {}
MenuStateStore.__index = MenuStateStore

function MenuStateStore.new()
	local self = setmetatable({}, MenuStateStore)
	self._state = MenuReducer.initialState() :: MenuState
	self._listeners = {} :: { (MenuState, MenuState, MenuAction) -> () }
	return self
end

function MenuStateStore:getState(): MenuState
	return self._state
end

function MenuStateStore:dispatch(action: MenuAction)
	local prev = self._state
	local next = MenuReducer.reduce(prev, action)
	if next == prev then
		return
	end
	self._state = next
	for _, listener in ipairs(self._listeners) do
		task.spawn(listener, prev, next, action)
	end
end

function MenuStateStore:subscribe(listener: (MenuState, MenuState, MenuAction) -> ()): () -> ()
	table.insert(self._listeners, listener)
	return function()
		for i, cb in ipairs(self._listeners) do
			if cb == listener then
				table.remove(self._listeners, i)
				break
			end
		end
	end
end

return MenuStateStore
