--!strict

local plugin = {
	id = "NotificationPanelPlugin",
	tier = "transient",
}

local queue = {}

function plugin.mount(_host)
	queue = {}
end

function plugin.onStateChanged(_prev, _next)
end

function plugin.onData(event)
	if type(event) ~= "table" then
		return
	end
	if event.type == "transient_enqueue" then
		table.insert(queue, event.payload)
	elseif event.type == "transient_dequeue" then
		if #queue > 0 then
			table.remove(queue, 1)
		end
	end
end

function plugin.unmount()
	queue = {}
end

return plugin