--!strict
-- Registry for networking channels, owned by the custom transport.

export type ChannelDirection = "server_to_client" | "client_to_server" | "bidirectional"
export type ChannelDefinition = {
	remote: string,
	remoteEvent: string?,
	remoteFunction: string?,
	qos: "CRITICAL" | "HIGH" | "NORMAL" | "BACKGROUND",
	direction: ChannelDirection,
	intents: { string }?,
	events: { string }?,
}

local ChannelRegistry = {}

local channels: { [string]: ChannelDefinition } = {}
local intentToChannel: { [string]: string } = {}
local eventToChannel: { [string]: string } = {}

local function cloneDefinition(def: ChannelDefinition): ChannelDefinition
	local copy: ChannelDefinition = {
		remote = def.remote,
		remoteEvent = def.remoteEvent,
		remoteFunction = def.remoteFunction,
		qos = def.qos,
		direction = def.direction,
		intents = if def.intents then table.clone(def.intents) else nil,
		events = if def.events then table.clone(def.events) else nil,
	}
	return copy
end

function ChannelRegistry.clear()
	for key in pairs(channels) do
		channels[key] = nil
	end
	for name in pairs(intentToChannel) do
		intentToChannel[name] = nil
	end
	for name in pairs(eventToChannel) do
		eventToChannel[name] = nil
	end
end

function ChannelRegistry.register(name: string, def: ChannelDefinition)
	assert(channels[name] == nil, `Channel '{name}' already registered`)
	local remoteEventName = def.remoteEvent or (def.remote .. "Event")
	local remoteFunctionName = def.remoteFunction
	local stored: ChannelDefinition = {
		remote = def.remote,
		remoteEvent = remoteEventName,
		remoteFunction = remoteFunctionName,
		qos = def.qos,
		direction = def.direction,
		intents = if def.intents then table.clone(def.intents) else nil,
		events = if def.events then table.clone(def.events) else nil,
	}
	channels[name] = stored
	if stored.intents then
		for _, intentName in ipairs(stored.intents) do
			intentToChannel[intentName] = name
		end
	end
	if stored.events then
		for _, eventName in ipairs(stored.events) do
			eventToChannel[eventName] = name
		end
	end
end

function ChannelRegistry.load(definitions: { [string]: ChannelDefinition })
	ChannelRegistry.clear()
	for name, def in pairs(definitions) do
		ChannelRegistry.register(name, def)
	end
end

function ChannelRegistry.get(name: string): ChannelDefinition?
	local def = channels[name]
	return if def then cloneDefinition(def) else nil
end

function ChannelRegistry.getChannelForIntent(intentName: string): string?
	return intentToChannel[intentName]
end

function ChannelRegistry.getChannelForEvent(eventName: string): string?
	return eventToChannel[eventName]
end

function ChannelRegistry.list(): { { name: string, definition: ChannelDefinition } }
	local result = {}
	for name, def in pairs(channels) do
		result[#result + 1] = {
			name = name,
			definition = cloneDefinition(def),
		}
	end
	table.sort(result, function(a, b)
		return a.name < b.name
	end)
	return result
end

return ChannelRegistry
