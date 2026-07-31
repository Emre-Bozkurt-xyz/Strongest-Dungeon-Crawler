--!strict
-- Attribute command senders.
--
-- Components call these; they do not build request payloads inline (R10). The wire format itself
-- lives on AttributesClient, which owns the store it has to update with the response -- this module
-- just gives the view layer a name to call that isn't a raw client method.

local AttributesClient = require(script.Parent.Parent.Parent.AttributesClient)

local AttributeActions = {}

function AttributeActions.spendPoint(target: string)
	task.spawn(function()
		AttributesClient.requestSpendPoint(target)
	end)
end

return AttributeActions
