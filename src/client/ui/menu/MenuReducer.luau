--!strict

local Types = require(script.Parent.PanelPluginTypes)

type MenuState = Types.MenuState
type MenuAction = Types.MenuAction
type MenuView = Types.MenuView

local function cloneMap<T>(value: { [string]: T }): { [string]: T }
	local out: { [string]: T } = {}
	for key, entry in pairs(value) do
		out[key] = entry
	end
	return out
end

local PRIMARY_BY_VIEW: { [MenuView]: string } = {
	system = "SystemPanel",
	inventory = "InventoryPanel",
	equipment = "EquipmentPanel",
}

local function resolveNextInspectState(inspect: Types.InspectState?, view: MenuView, modalOpen: boolean): Types.InspectState?
	if inspect == nil then
		return nil
	end
	if not modalOpen then
		return nil
	end
	if inspect.source == "inventory" and view ~= "inventory" then
		return nil
	end
	if inspect.source == "equipment" and view ~= "equipment" then
		return nil
	end
	if view == "system" then
		return nil
	end
	return inspect
end

local function deriveLayout(state: MenuState): MenuState
	local view = state.modal.view
	local primary = PRIMARY_BY_VIEW[view]
	local side: { string } = {}
	if state.inspect ~= nil and view ~= "system" then
		table.insert(side, "ItemInspectPanel")
	end

	local modal = {
		open = state.modal.open,
		view = view,
		primaryPanelId = primary,
		sidePanelIds = side,
	}

	return {
		modal = modal,
		contextPanels = state.contextPanels,
		transientQueue = state.transientQueue,
		inspect = state.inspect,
	}
end

local MenuReducer = {}

function MenuReducer.initialState(): MenuState
	return {
		modal = {
			open = false,
			view = "system",
			primaryPanelId = "SystemPanel",
			sidePanelIds = {},
		},
		contextPanels = {},
		transientQueue = {},
		inspect = nil,
	}
end

function MenuReducer.reduce(state: MenuState, action: MenuAction): MenuState
	if action.type == "OPEN_MODAL" then
		local nextView = action.view or state.modal.view
		local nextInspect = resolveNextInspectState(state.inspect, nextView, true)
		local next = {
			modal = {
				open = true,
				view = nextView,
				primaryPanelId = state.modal.primaryPanelId,
				sidePanelIds = {},
			},
			contextPanels = cloneMap(state.contextPanels),
			transientQueue = table.clone(state.transientQueue),
			inspect = nextInspect,
		}
		return deriveLayout(next)
	end

	if action.type == "CLOSE_MODAL" then
		local nextInspect = resolveNextInspectState(state.inspect, state.modal.view, false)
		local next = {
			modal = {
				open = false,
				view = state.modal.view,
				primaryPanelId = state.modal.primaryPanelId,
				sidePanelIds = {},
			},
			contextPanels = cloneMap(state.contextPanels),
			transientQueue = table.clone(state.transientQueue),
			inspect = nextInspect,
		}
		return deriveLayout(next)
	end

	if action.type == "SET_VIEW" and action.view ~= nil then
		local nextInspect = resolveNextInspectState(state.inspect, action.view, state.modal.open)
		local next = {
			modal = {
				open = state.modal.open,
				view = action.view,
				primaryPanelId = state.modal.primaryPanelId,
				sidePanelIds = {},
			},
			contextPanels = cloneMap(state.contextPanels),
			transientQueue = table.clone(state.transientQueue),
			inspect = nextInspect,
		}
		return deriveLayout(next)
	end

	if action.type == "SET_INSPECT" then
		if action.source == nil then
			return state
		end
		local next = {
			modal = {
				open = state.modal.open,
				view = state.modal.view,
				primaryPanelId = state.modal.primaryPanelId,
				sidePanelIds = {},
			},
			contextPanels = cloneMap(state.contextPanels),
			transientQueue = table.clone(state.transientQueue),
			inspect = {
				source = action.source,
				payload = action.payload,
			},
		}
		return deriveLayout(next)
	end

	if action.type == "CLEAR_INSPECT" then
		local next = {
			modal = {
				open = state.modal.open,
				view = state.modal.view,
				primaryPanelId = state.modal.primaryPanelId,
				sidePanelIds = {},
			},
			contextPanels = cloneMap(state.contextPanels),
			transientQueue = table.clone(state.transientQueue),
			inspect = nil,
		}
		return deriveLayout(next)
	end

	if action.type == "SET_CONTEXT_PANEL" and action.panelId ~= nil then
		local map = cloneMap(state.contextPanels)
		map[action.panelId] = action.visible == true
		return {
			modal = state.modal,
			contextPanels = map,
			transientQueue = table.clone(state.transientQueue),
			inspect = state.inspect,
		}
	end

	if action.type == "ENQUEUE_TRANSIENT" then
		local queue = table.clone(state.transientQueue)
		table.insert(queue, action.transient)
		return {
			modal = state.modal,
			contextPanels = cloneMap(state.contextPanels),
			transientQueue = queue,
			inspect = state.inspect,
		}
	end

	if action.type == "DEQUEUE_TRANSIENT" then
		local queue = table.clone(state.transientQueue)
		if #queue > 0 then
			table.remove(queue, 1)
		end
		return {
			modal = state.modal,
			contextPanels = cloneMap(state.contextPanels),
			transientQueue = queue,
			inspect = state.inspect,
		}
	end

	return state
end

return MenuReducer
