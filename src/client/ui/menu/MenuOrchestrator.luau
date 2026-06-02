--!strict

local Types = require(script.Parent.PanelPluginTypes)
local MenuStateStore = require(script.Parent.MenuStateStore)
local PanelPluginRegistry = require(script.Parent.PanelPluginRegistry)
local MenuInputBridge = require(script.Parent.MenuInputBridge)
local MenuMotionBridge = require(script.Parent.MenuMotionBridge)
local MenuRigRuntime = require(script.Parent.MenuRigRuntime)

local SystemPanelPlugin = require(script.Parent.plugins.SystemPanelPlugin)
local InventoryPanelPlugin = require(script.Parent.plugins.InventoryPanelPlugin)
local EquipmentPanelPlugin = require(script.Parent.plugins.EquipmentPanelPlugin)
local ItemInspectPanelPlugin = require(script.Parent.plugins.ItemInspectPanelPlugin)
local StatusPreviewPanelPlugin = require(script.Parent.plugins.StatusPreviewPanelPlugin)
local NotificationPanelPlugin = require(script.Parent.plugins.NotificationPanelPlugin)
local QuestPanelPlugin = require(script.Parent.plugins.QuestPanelPlugin)
local QuickActivationPanelPlugin = require(script.Parent.plugins.QuickActivationPanelPlugin)

type MenuView = Types.MenuView
type MenuState = Types.MenuState
type InspectSource = Types.InspectSource

local MenuOrchestrator = {}

local _store = nil
local _registry = nil
local _disconnect = nil
local _initialized = false

local VIEWS: { MenuView } = { "system", "inventory", "equipment" }

local function ensureInit()
	if _initialized then
		return
	end

	_store = MenuStateStore.new()
	_registry = PanelPluginRegistry.new()

	_registry:register(SystemPanelPlugin)
	_registry:register(InventoryPanelPlugin)
	_registry:register(EquipmentPanelPlugin)
	_registry:register(ItemInspectPanelPlugin)
	_registry:register(StatusPreviewPanelPlugin)
	_registry:register(NotificationPanelPlugin)
	_registry:register(QuestPanelPlugin)
	_registry:register(QuickActivationPanelPlugin)

	_registry:mountAll({
		getState = function(): MenuState
			return _store:getState()
		end,
		dispatch = function(action)
			_store:dispatch(action)
		end,
		publish = function(event)
			_registry:broadcast(event)
		end,
	})

	_disconnect = _store:subscribe(function(prev, next, _action)
		MenuInputBridge.apply(next.modal.open)
		MenuMotionBridge.onModalStateChanged(prev.modal.open, next.modal.open)
		MenuRigRuntime.get():applyMenuState(next)
		_registry:onStateChanged(prev, next)
	end)

	_initialized = true
end

local function getState(): MenuState
	ensureInit()
	return _store:getState()
end

local function dispatch(action)
	ensureInit()
	_store:dispatch(action)
end

function MenuOrchestrator.init()
	ensureInit()
	MenuRigRuntime.get():applyMenuState(_store:getState())
end

function MenuOrchestrator.open(view: MenuView?)
	dispatch({ type = "OPEN_MODAL", view = view })
end

function MenuOrchestrator.close()
	dispatch({ type = "CLOSE_MODAL" })
end

function MenuOrchestrator.setView(view: MenuView)
	dispatch({ type = "SET_VIEW", view = view })
end

function MenuOrchestrator.toggleView(view: MenuView)
	local state = getState()
	if not state.modal.open then
		MenuOrchestrator.open(view)
		return
	end
	if state.modal.view == view then
		MenuOrchestrator.close()
		return
	end
	MenuOrchestrator.setView(view)
end

function MenuOrchestrator.cycleView(direction: number?): MenuView
	local state = getState()
	local idx = 1
	for i, view in ipairs(VIEWS) do
		if view == state.modal.view then
			idx = i
			break
		end
	end
	local dir = if (direction or 1) >= 0 then 1 else -1
	local nextIdx = idx + dir
	if nextIdx < 1 then
		nextIdx = #VIEWS
	elseif nextIdx > #VIEWS then
		nextIdx = 1
	end
	local nextView = VIEWS[nextIdx]
	MenuOrchestrator.setView(nextView)
	return nextView
end

function MenuOrchestrator.setInspect(source: InspectSource, payload: any)
	dispatch({ type = "SET_INSPECT", source = source, payload = payload })
	_registry:broadcast({ type = "inspect_set", source = source, payload = payload })
end

function MenuOrchestrator.clearInspect()
	dispatch({ type = "CLEAR_INSPECT" })
	_registry:broadcast({ type = "inspect_clear" })
end

function MenuOrchestrator.enqueueTransient(payload: any)
	dispatch({ type = "ENQUEUE_TRANSIENT", transient = payload })
	_registry:broadcast({ type = "transient_enqueue", payload = payload })
end

function MenuOrchestrator.dequeueTransient()
	dispatch({ type = "DEQUEUE_TRANSIENT" })
	_registry:broadcast({ type = "transient_dequeue" })
end

function MenuOrchestrator.isOpen(): boolean
	return getState().modal.open
end

function MenuOrchestrator.getView(): MenuView
	return getState().modal.view
end

function MenuOrchestrator.getState(): MenuState
	return getState()
end

function MenuOrchestrator.isGameplayBlocked(): boolean
	return MenuInputBridge.isGameplayBlocked()
end

function MenuOrchestrator.onChanged(callback: (MenuState, MenuState, any) -> ()): () -> ()
	ensureInit()
	return _store:subscribe(callback)
end

function MenuOrchestrator.destroy()
	if _disconnect then
		_disconnect()
		_disconnect = nil
	end
	if _registry then
		_registry:unmountAll()
	end
	_registry = nil
	_store = nil
	MenuMotionBridge.clearEntryBasis()
	MenuInputBridge.apply(false)
	MenuRigRuntime.get():applyMenuState({
		modal = {
			open = false,
			view = "system",
			primaryPanelId = "SystemPanel",
			sidePanelIds = {},
		},
		contextPanels = {},
		transientQueue = {},
		inspect = nil,
	})
	_initialized = false
end

return MenuOrchestrator
