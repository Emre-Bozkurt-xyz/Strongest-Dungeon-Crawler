--!strict
-- Client-side attributes display and handling
-- Receives attribute updates from server

local Warp = require(game.ReplicatedStorage.Packages.warp)
local AttributesConfig = require(game.ReplicatedStorage.Shared.AttributesConfig)

type AttributeType = AttributesConfig.AttributeType
type AttributeData = AttributesConfig.AttributeData
type PlayerAttributes = AttributesConfig.PlayerAttributes

local AttributesClient = {}
local currentAttributes: PlayerAttributes? = nil

-- Warp events for networking
local attributesUpdateEvent = Warp.Client("AttributesUpdate")
local attributesRequestEvent = Warp.Client("AttributesRequest")

-- Handle incoming attribute updates from server
local function handleAttributesUpdate(attributes: PlayerAttributes)
	currentAttributes = attributes
	print("Received attributes update from server")
end

-- Public functions
function AttributesClient.getCurrentAttributes(): PlayerAttributes?
	return currentAttributes
end

function AttributesClient.requestAttributesUpdate()
	attributesRequestEvent:Fire(true)
end

-- Connect to server events
attributesUpdateEvent:Connect(handleAttributesUpdate)

-- Request initial attributes
AttributesClient.requestAttributesUpdate()

print("AttributesClient initialized")
return AttributesClient
