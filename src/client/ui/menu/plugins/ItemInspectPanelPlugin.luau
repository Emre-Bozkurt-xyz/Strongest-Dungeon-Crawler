--!strict

local Runtime = require(script.Parent.Parent.Parent.runtime.ItemInspectRuntime)

local plugin = {
	id = "ItemInspectPanelPlugin",
	tier = "modal",
}

local function getRuntime()
	return Runtime.tryInit()
end

local function shouldShowInspect(next): boolean
	local inspect = next.inspect
	if inspect == nil then
		return false
	end
	return next.modal.open and next.modal.view ~= "system"
end

local function shouldResetFollow(prev, next): boolean
	local prevVisible = shouldShowInspect(prev)
	local nextVisible = shouldShowInspect(next)
	if not nextVisible then
		return false
	end
	if not prevVisible then
		return true
	end
	if prev.inspect ~= next.inspect then
		return true
	end
	return prev.modal.view ~= next.modal.view
end

function plugin.mount(_host)
	local runtime = getRuntime()
	if runtime then
		runtime:setInspectState(nil)
		runtime:setVisible(false, 0)
	end
end

function plugin.onStateChanged(prev, next)
	local runtime = getRuntime()
	if not runtime then
		return
	end

	runtime:setInspectState(next.inspect)
	if shouldResetFollow(prev, next) then
		runtime:resetFollow()
	end
	runtime:setVisible(shouldShowInspect(next), 0.2)
end

function plugin.onData(_event)
end

function plugin.unmount()
	local runtime = getRuntime()
	if runtime then
		runtime:setInspectState(nil)
		runtime:setVisible(false, 0)
	end
end

return plugin
