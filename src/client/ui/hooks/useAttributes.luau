--!strict
-- Player attribute values, read from AttributesClient.
--
-- AttributesClient.onChanged returns a connection object with :Disconnect(), not an unsubscribe
-- function -- a fourth subscription shape across the client stores. Adapting it here is exactly why
-- R4 uses per-store hooks instead of one generic useStore.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local AttributesClient = require(script.Parent.Parent.Parent.AttributesClient)

local function useAttributes(): AttributesClient.AttributesData?
	local data, setData = React.useState(AttributesClient.getCurrentData())

	React.useEffect(function()
		local connection = AttributesClient.onChanged(function(next)
			setData(next)
		end)
		return function()
			connection.Disconnect()
		end
	end, {})

	return data
end

return useAttributes
