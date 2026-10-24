--!strict
-- The live System notices, re-rendering when NotificationClient publishes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local NotificationClient = require(script.Parent.Parent.controllers.NotificationClient)

local function useNotifications(): { NotificationClient.Notice }
	local notices, setNotices = React.useState(NotificationClient.getSnapshot)

	React.useEffect(function()
		local disconnect = NotificationClient.onChanged(function()
			setNotices(NotificationClient.getSnapshot())
		end)
		-- A push may have landed between first render and this effect running.
		setNotices(NotificationClient.getSnapshot())
		return disconnect
	end, {})

	return notices
end

return useNotifications
