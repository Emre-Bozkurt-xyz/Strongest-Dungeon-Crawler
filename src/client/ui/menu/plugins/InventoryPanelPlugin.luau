--!strict

local Runtime = require(script.Parent.Parent.Parent.runtime.InventoryMenuRuntime)

local plugin = {
	id = "InventoryPanelPlugin",
	tier = "modal",
}

local inv = nil
local hostRef = nil

local function bindInspectSelection(runtime)
	if not runtime or not hostRef then
		return
	end
	runtime:setInspectSelectionHandler(function(uid: string?)
		local state = hostRef.getState()
		local inspect = state.inspect
		if type(uid) == "string" and uid ~= "" then
			hostRef.dispatch({
				type = "SET_INSPECT",
				source = "inventory",
				payload = {
					uid = uid,
				},
			})
			return
		end
		if inspect ~= nil and inspect.source == "inventory" then
			hostRef.dispatch({
				type = "CLEAR_INSPECT",
			})
		end
	end)
end

function plugin.mount(host)
	hostRef = host
	inv = Runtime.tryInit()
	bindInspectSelection(inv)
end

function plugin.onStateChanged(prev, next)
	if not inv then
		inv = Runtime.tryInit()
		bindInspectSelection(inv)
	end
	if not inv then
		return
	end
	if next.modal.open and ((not prev.modal.open) or prev.modal.view ~= next.modal.view or prev.inspect ~= next.inspect) then
		inv:setMenuView(next.modal.view)
	elseif (not next.modal.open) and prev.modal.open then
		inv:hideAll()
	end
end

function plugin.onData(_event)
end

function plugin.unmount()
	if inv then
		inv:setInspectSelectionHandler(nil)
		inv:hideAll()
	end
	hostRef = nil
end

return plugin
