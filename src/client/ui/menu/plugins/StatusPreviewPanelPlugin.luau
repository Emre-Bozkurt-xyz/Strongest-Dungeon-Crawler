--!strict

local WorldGUIManager = require(script.Parent.Parent.Parent.Parent.WorldGUIManager)

local plugin = {
	id = "StatusPreviewPanelPlugin",
	tier = "context",
}

function plugin.mount(_host)
end

function plugin.onStateChanged(_prev, next)
	local wgm = WorldGUIManager.getInstance()
	if next.modal.open then
		wgm:setPanelVisibility("StatusPreview", false, 0.2, workspace)
	else
		wgm:setPanelVisibility("StatusPreview", true, 0.2, workspace)
	end
end

function plugin.onData(_event)
end

function plugin.unmount()
end

return plugin