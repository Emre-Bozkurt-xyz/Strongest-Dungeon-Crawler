--!strict

local Runtime = require(script.Parent.Parent.Parent.runtime.EquipmentMenuRuntime)

local plugin = {
	id = "EquipmentPanelPlugin",
	tier = "modal",
}

local mounted = false
local hostRef = nil

local function bindInspectSelection(runtime)
	runtime:setInspectSelectionHandler(function(uid: string?)
		local host = hostRef
		if not host then
			return
		end

		if uid then
			host.dispatch({
				type = "SET_INSPECT",
				source = "equipment",
				payload = { uid = uid },
			})
			return
		end

		local state = host.getState()
		if state.inspect and state.inspect.source == "equipment" then
			host.dispatch({
				type = "CLEAR_INSPECT",
			})
		end
	end)
end

function plugin.mount(host)
	local runtime = Runtime.tryInit()
	hostRef = host
	if runtime then
		bindInspectSelection(runtime)
	end
	mounted = true
end

function plugin.onStateChanged(prev, next)
	if not mounted then
		return
	end
	local shouldShow = next.modal.open and next.modal.view == "equipment"
	if shouldShow then
		Runtime.show()
	elseif prev.modal.open and prev.modal.view == "equipment" then
		Runtime.clearSelection()
		Runtime.hide()
	end
end

function plugin.onData(_event)
end

function plugin.unmount()
	mounted = false
	local runtime = Runtime.tryInit()
	if runtime then
		runtime:setInspectSelectionHandler(nil)
	end
	Runtime.clearSelection()
	Runtime.hide()
	hostRef = nil
end

return plugin
