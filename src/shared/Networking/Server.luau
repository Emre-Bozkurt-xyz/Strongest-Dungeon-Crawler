--!strict
-- Server-side entrypoint for the custom networking transport.

local Dispatcher = require(script.Parent.Dispatcher)

type AnyConfig = { [string]: any }

return function(config: AnyConfig?)
	local merged: AnyConfig = {}
	if config then
		for key, value in pairs(config) do
			merged[key] = value
		end
	end
	merged.peer = "server"
	return Dispatcher.new(merged)
end
