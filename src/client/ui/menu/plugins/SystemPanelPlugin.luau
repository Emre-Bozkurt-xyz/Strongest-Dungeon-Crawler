--!strict

local Runtime = require(script.Parent.Parent.Parent.runtime.SystemPanelRuntime)

local plugin = {
	id = "SystemPanelPlugin",
	tier = "modal",
}

local mounted = false

function plugin.mount(_host)
	mounted = true
	Runtime.get()
end

function plugin.onStateChanged(prev, next)
	if not mounted then
		return
	end
	if (not prev.modal.open) and next.modal.open then
		Runtime.show()
	end
	if prev.modal.open and (not next.modal.open) then
		Runtime.hide()
	end
	if next.modal.open and ((not prev.modal.open) or prev.modal.view ~= next.modal.view) then
		Runtime.setMenuView(next.modal.view)
	end
end

function plugin.onData(_event)
end

function plugin.unmount()
	mounted = false
	Runtime.hide()
end

return plugin
