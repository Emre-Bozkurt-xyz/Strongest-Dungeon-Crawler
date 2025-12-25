--!strict
-- Core dispatcher for the custom networking transport. Transport adapters will extend this.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local container = script.Parent

local EnvelopeModule = require(container.Envelope)
local ChannelRegistry = require(container.ChannelRegistry)
local ChannelDefinitions = require(container.Channels)
local StatsModule = require(container.Stats)
local ReplayBufferModule = require(container.ReplayBuffer)

export type QoS = "CRITICAL" | "HIGH" | "NORMAL" | "BACKGROUND"

export type Meta = {
	seq: number,
	qos: QoS,
	tsSent: number,
	tsAck: number?,
	playerId: number?,
	traceId: string?,
	flags: { [string]: boolean }?,
}

export type EnvelopeType = {
	name: string,
	payload: any,
	meta: Meta,
}

type StatsType = {
	increment: (StatsType, string, number?) -> (),
	observeLatency: (StatsType, string, number) -> (),
	reset: (StatsType) -> (),
	snapshot: (StatsType) -> StatsModule.Snapshot,
	dump: (StatsType) -> (),
}

type ReplayBufferType = {
	push: (ReplayBufferType, EnvelopeType) -> (),
	iterate: (ReplayBufferType) -> { EnvelopeType },
	clear: (ReplayBufferType) -> (),
}

type RemoteBundle = {
	event: RemoteEvent?,
	request: RemoteFunction?,
}

export type ReplayConfig = {
	enabled: boolean?,
	bufferSize: number?,
}

export type ChannelDefinition = ChannelRegistry.ChannelDefinition

export type SendOptions = {
	qos: QoS?,
	playerId: number?,
	traceId: string?,
	flags: { [string]: boolean }?,
	tsOverride: number?,
	seqOverride: number?,
	targets: Player | { Player }?,
}

export type Config = {
	peer: "client" | "server",
	channelRegistry: { [string]: ChannelDefinition }?,
	stats: StatsType?,
	replay: ReplayConfig?,
}

type Listener = (payload: any, meta: Meta) -> ()

type RequestHandler = (payload: any, meta: Meta, context: { player: Player? }) -> any

type ListenerBucket = {
	handlers: { Listener },
}

type TransportKind = "event" | "request"

type RecordContext = {
	channel: string?,
	transport: TransportKind?,
}

type DispatcherImpl = {
	_peer: "client" | "server",
	_stats: StatsType,
	_replay: ReplayBufferType?,
	_listeners: { [string]: ListenerBucket },
	_channelDefinitions: { [string]: ChannelDefinition },
	_channelRemotes: { [string]: RemoteBundle },
	_connections: { RBXScriptConnection },
	_remoteFolder: Instance?,
	_requestHandlers: { [string]: RequestHandler },
}

local Dispatcher = {}
Dispatcher.__index = Dispatcher

local NETWORK_FOLDER_NAME = "NetworkChannels"

local function ensureRemoteFolder(peer: "client" | "server"): Instance
	local folder = ReplicatedStorage:FindFirstChild(NETWORK_FOLDER_NAME)
	if folder and folder:IsA("Folder") then
		return folder
	end
	if peer == "server" then
		folder = Instance.new("Folder")
		folder.Name = NETWORK_FOLDER_NAME
		folder.Parent = ReplicatedStorage
		return folder
	end
	folder = ReplicatedStorage:WaitForChild(NETWORK_FOLDER_NAME, 5)
	assert(folder and folder:IsA("Folder"), `Networking folder '{NETWORK_FOLDER_NAME}' not found in ReplicatedStorage`)
	return folder
end

local function normalizeTargets(optionTargets: any?): { Player }
	if optionTargets == nil then
		return Players:GetPlayers()
	end
	if typeof(optionTargets) == "Instance" and optionTargets:IsA("Player") then
		return { optionTargets }
	end
	if typeof(optionTargets) == "table" then
		local cast = {} :: { Player }
		for _, value in ipairs(optionTargets) do
			if typeof(value) == "Instance" and value:IsA("Player") then
				cast[#cast + 1] = value
			end
		end
		return cast
	end
	return {}
end

local function canSendToPeer(def: ChannelDefinition, peer: "client" | "server"): boolean
	if peer == "client" then
		return def.direction ~= "server_to_client"
	else
		return def.direction ~= "client_to_server"
	end
end

local function canReceiveFromPeer(def: ChannelDefinition, peer: "client" | "server"): boolean
	if peer == "client" then
		return def.direction ~= "client_to_server"
	else
		return def.direction ~= "server_to_client"
	end
end

function Dispatcher.new(config: Config)
	assert(config, "Dispatcher.new requires a config table")
	assert(config.peer == "client" or config.peer == "server", "Dispatcher peer must be 'client' or 'server'")

	local stats = (config.stats or StatsModule.new()) :: StatsType
	local replayBuffer = nil :: ReplayBufferType?
	local replayConfig = config.replay
	if replayConfig and replayConfig.enabled then
		replayBuffer = ReplayBufferModule.new(replayConfig.bufferSize) :: ReplayBufferType
	end

	local remoteFolder = ensureRemoteFolder(config.peer)

	local self = setmetatable(
		{
			_peer = config.peer,
			_stats = stats,
			_replay = replayBuffer,
			_listeners = {} :: { [string]: ListenerBucket },
			_channelDefinitions = {} :: { [string]: ChannelDefinition },
			_channelRemotes = {} :: { [string]: RemoteBundle },
			_connections = {},
			_remoteFolder = remoteFolder,
			_requestHandlers = {},
		} :: DispatcherImpl,
		Dispatcher
	)

	if config.channelRegistry then
		ChannelRegistry.load(config.channelRegistry)
	end

	for _, entry in ipairs(ChannelRegistry.list()) do
		self._channelDefinitions[entry.name] = entry.definition
		self:_ensureChannel(entry.name)
	end

	return self
end

local function snapshotHandlers(bucket: ListenerBucket): { Listener }
	local copy = {}
	for index = 1, #bucket.handlers do
		copy[index] = bucket.handlers[index]
	end
	return copy
end

function Dispatcher:on(eventName: string, handler: Listener): () -> ()
	assert(type(handler) == "function", "Dispatcher:on expects a function handler")
	local channelName = ChannelRegistry.getChannelForEvent(eventName)
	if not channelName then
		channelName = ChannelRegistry.getChannelForIntent(eventName)
	end
	if channelName then
		((self :: any)._ensureChannel)(self, channelName)
	end
	local bucket = (self :: DispatcherImpl)._listeners[eventName]
	if not bucket then
		bucket = { handlers = {} }
		(self :: DispatcherImpl)._listeners[eventName] = bucket
	end
	bucket.handlers[#bucket.handlers + 1] = handler

	local disconnected = false
	local function disconnect()
		if disconnected then
			return
		end
		disconnected = true
		local handlers = bucket.handlers
		for index = #handlers, 1, -1 do
			if handlers[index] == handler then
				table.remove(handlers, index)
				break
			end
		end
	end

	return disconnect
end

function Dispatcher:_emitLocal(eventName: string, payload: any, meta: Meta)
	local bucket = (self :: DispatcherImpl)._listeners[eventName]
	if not bucket then
		return
	end
	local handlers = snapshotHandlers(bucket)
	for _, handler in ipairs(handlers) do
		local success = pcall(handler, payload, meta)
		if not success then
			warn(`Dispatcher handler for {eventName} failed`)
		end
	end
end

function Dispatcher:_record(direction: "incoming" | "outgoing", envelope: EnvelopeType, context: RecordContext?)
	local selfImpl = self :: DispatcherImpl
	selfImpl._stats:increment(`{direction}:{envelope.name}`)

	local channelName = if context then context.channel else nil
	local transport = if context then context.transport else nil
	if channelName == nil or transport == nil then
		local resolvedChannel = ChannelRegistry.getChannelForEvent(envelope.name)
		if resolvedChannel then
			channelName = channelName or resolvedChannel
			transport = transport or "event"
		else
			resolvedChannel = ChannelRegistry.getChannelForIntent(envelope.name)
			if resolvedChannel then
				channelName = channelName or resolvedChannel
				transport = transport or "request"
			end
		end
	end

	if channelName then
		selfImpl._stats:increment(`channel:{direction}:{channelName}`)
	end
	if transport then
		selfImpl._stats:increment(`transport:{direction}:{transport}`)
	end

	local qos = envelope.meta.qos
	if qos then
		selfImpl._stats:increment(`qos:{direction}:{qos}`)
	end

	local buffer = selfImpl._replay
	if buffer then
		buffer:push(envelope)
	end
	local meta: Meta = envelope.meta
	if meta.tsAck and meta.tsAck >= meta.tsSent then
		local latency = meta.tsAck - meta.tsSent
		selfImpl._stats:observeLatency(`latency:{envelope.name}`, latency)
		if channelName then
			selfImpl._stats:observeLatency(`latency:channel:{channelName}`, latency)
		end
		if transport then
			selfImpl._stats:observeLatency(`latency:transport:{transport}`, latency)
		end
	end
end

function Dispatcher:handleIncoming(envelope: EnvelopeType, ackTs: number?, context: RecordContext?)
	if ackTs then
		envelope.meta.tsAck = ackTs
	end
	self:_record("incoming", envelope, context)
	self:_emitLocal(envelope.name, envelope.payload, envelope.meta)
end

function Dispatcher:_coerceEnvelope(raw: any): EnvelopeType?
	if typeof(raw) ~= "table" then
		return nil
	end
	local name = raw.name
	local payload = raw.payload
	local meta = raw.meta
	if typeof(name) ~= "string" or typeof(meta) ~= "table" then
		return nil
	end
	return {
		name = name,
		payload = payload,
		meta = meta :: Meta,
	}
end

function Dispatcher:_ensureChannel(name: string)
	local impl = (self :: any) :: DispatcherImpl
	if impl._channelRemotes[name] then
		return
	end
	local definition = impl._channelDefinitions[name]
	if not definition then
		local fetched = ChannelRegistry.get(name)
		if not fetched then
			local baseDefinition = ChannelDefinitions[name]
			if baseDefinition then
				ChannelRegistry.register(name, baseDefinition)
				fetched = ChannelRegistry.get(name)
			end
		end
		assert(fetched, `Channel '{name}' is not registered`)
		definition = fetched
		impl._channelDefinitions[name] = definition
	end

	local folder = impl._remoteFolder
	assert(folder, "Networking remote folder missing")

	local bundle: RemoteBundle = { event = nil, request = nil }

	local remoteEventName = definition.remoteEvent
	if remoteEventName then
		local remoteEvent = folder:FindFirstChild(remoteEventName) :: RemoteEvent?
		if not remoteEvent then
			if impl._peer == "server" then
				local newRemote = Instance.new("RemoteEvent")
				newRemote.Name = remoteEventName
				newRemote.Parent = folder
				remoteEvent = newRemote
			else
				-- Client: Wait indefinitely for server to create the RemoteEvent
				-- No rush - listeners will connect once server is ready
				remoteEvent = folder:WaitForChild(remoteEventName) :: RemoteEvent
			end
		end
		assert(
			remoteEvent and remoteEvent:IsA("RemoteEvent"),
			`RemoteEvent '{remoteEventName}' is not a RemoteEvent for channel '{name}'`
		)
		bundle.event = remoteEvent
		self:_bindEventChannel(name, definition, remoteEvent)
	end

	local remoteFunctionName = definition.remoteFunction
	if remoteFunctionName then
		local remoteFunction = folder:FindFirstChild(remoteFunctionName) :: RemoteFunction?
		if not remoteFunction then
			if impl._peer == "server" then
				local newRemote = Instance.new("RemoteFunction")
				newRemote.Name = remoteFunctionName
				newRemote.Parent = folder
				remoteFunction = newRemote
			else
				-- Client: Wait indefinitely for server to create the RemoteFunction
				remoteFunction = folder:WaitForChild(remoteFunctionName) :: RemoteFunction
			end
		end
		assert(
			remoteFunction and remoteFunction:IsA("RemoteFunction"),
			`RemoteFunction '{remoteFunctionName}' missing for channel '{name}'`
		)
		bundle.request = remoteFunction
		self:_bindRequestChannel(name, definition, remoteFunction)
	end

	impl._channelRemotes[name] = bundle
end

function Dispatcher:_bindEventChannel(channelName: string, definition: ChannelDefinition, remoteEvent: RemoteEvent)
	local impl = (self :: any) :: DispatcherImpl
	if impl._peer == "client" then
		if canReceiveFromPeer(definition, "client") then
			local connection = remoteEvent.OnClientEvent:Connect(function(rawEnvelope)
				local envelope = self:_coerceEnvelope(rawEnvelope)
				if not envelope then
					warn(`Dispatcher received invalid envelope on channel {channelName}`)
					return
				end
				self:handleIncoming(envelope, nil, { channel = channelName, transport = "event" })
			end)
			impl._connections[#impl._connections + 1] = connection
		end
	else
		if canReceiveFromPeer(definition, "server") then
			local connection = remoteEvent.OnServerEvent:Connect(function(player: Player, rawEnvelope)
				local envelope = self:_coerceEnvelope(rawEnvelope)
				if not envelope then
					warn(`Dispatcher received invalid envelope from {player.Name} on channel {channelName}`)
					return
				end
				envelope.meta.playerId = envelope.meta.playerId or player.UserId
				self:handleIncoming(envelope, nil, { channel = channelName, transport = "event" })
			end)
			impl._connections[#impl._connections + 1] = connection
		end
	end
end

function Dispatcher:_bindRequestChannel(
	channelName: string,
	definition: ChannelDefinition,
	remoteFunction: RemoteFunction
)
	local impl = (self :: any) :: DispatcherImpl
	if impl._peer == "server" then
		if canReceiveFromPeer(definition, "server") then
			remoteFunction.OnServerInvoke = function(player: Player, rawEnvelope)
				local envelope = self:_coerceEnvelope(rawEnvelope)
				if not envelope then
					warn(`Dispatcher received invalid request from {player.Name} on channel {channelName}`)
					return nil
				end
				envelope.meta.playerId = envelope.meta.playerId or player.UserId
				return self:_handleRequestInvocation(channelName, envelope, player)
			end
		end
	else
		if canReceiveFromPeer(definition, "client") then
			remoteFunction.OnClientInvoke = function(rawEnvelope)
				local envelope = self:_coerceEnvelope(rawEnvelope)
				if not envelope then
					warn(`Dispatcher received invalid request on client channel {channelName}`)
					return nil
				end
				local localPlayer = Players.LocalPlayer
				envelope.meta.playerId = envelope.meta.playerId or (localPlayer and localPlayer.UserId)
				return self:_handleRequestInvocation(channelName, envelope, localPlayer)
			end
		end
	end
end

function Dispatcher:_getChannel(channelName: string): (ChannelDefinition, RemoteBundle)
	self:_ensureChannel(channelName)
	local impl = (self :: any) :: DispatcherImpl
	local definition = impl._channelDefinitions[channelName]
	assert(definition, `Channel '{channelName}' is not registered`)
	local bundle = impl._channelRemotes[channelName]
	assert(bundle, `Channel '{channelName}' is not initialised`)
	return definition, bundle
end

function Dispatcher:_handleRequestInvocation(channelName: string, envelope: EnvelopeType, player: Player?): any
	local impl = (self :: any) :: DispatcherImpl
	local handler = impl._requestHandlers[envelope.name]
	local response = nil
	if handler then
		local ok, result = pcall(handler, envelope.payload, envelope.meta, { player = player })
		if ok then
			response = result
		else
			warn(`Dispatcher request handler for {envelope.name} on {channelName} failed: {result}`)
		end
	else
		warn(`Dispatcher received request '{envelope.name}' on channel '{channelName}' with no handler registered`)
	end
	local ackTs = os.clock()
	self:handleIncoming(envelope, ackTs, { channel = channelName, transport = "request" })
	return response
end

local function buildCreateOptions(options: SendOptions?): EnvelopeModule.CreateOptions?
	if not options then
		return nil
	end
	return {
		qos = options.qos,
		playerId = options.playerId,
		traceId = options.traceId,
		flags = options.flags,
		tsOverride = options.tsOverride,
		seqOverride = options.seqOverride,
	}
end

function Dispatcher:_buildEnvelope(name: string, payload: any, options: SendOptions?): EnvelopeType
	local envelope = EnvelopeModule.create(name, payload, buildCreateOptions(options))
	local impl = (self :: any) :: DispatcherImpl
	if impl._peer == "client" and envelope.meta.playerId == nil then
		local localPlayer = Players.LocalPlayer
		if localPlayer then
			envelope.meta.playerId = localPlayer.UserId
		end
	end
	return envelope
end

function Dispatcher:_sendEvent(
	channelName: string,
	definition: ChannelDefinition,
	bundle: RemoteBundle,
	envelope: EnvelopeType,
	options: SendOptions?
)
	local impl = (self :: any) :: DispatcherImpl
	local remoteEvent = bundle.event
	assert(remoteEvent, `Channel '{channelName}' does not have a RemoteEvent bound`)
	if impl._peer == "client" then
		assert(canSendToPeer(definition, "client"), `Channel '{channelName}' disallows client emission`)
		remoteEvent:FireServer(envelope)
	else
		assert(canSendToPeer(definition, "server"), `Channel '{channelName}' disallows server emission`)
		local targets = normalizeTargets(options and options.targets)
		if #targets == 0 then
			remoteEvent:FireAllClients(envelope)
		else
			for _, player in ipairs(targets) do
				remoteEvent:FireClient(player, envelope)
			end
		end
	end
	self:_record("outgoing", envelope, { channel = channelName, transport = "event" })
end

function Dispatcher:_invokeRequest(
	channelName: string,
	definition: ChannelDefinition,
	bundle: RemoteBundle,
	envelope: EnvelopeType,
	options: SendOptions?
): any
	local impl = (self :: any) :: DispatcherImpl
	local remoteFunction = bundle.request
	assert(remoteFunction, `Channel '{channelName}' does not have a RemoteFunction bound`)
	local response
	if impl._peer == "client" then
		assert(canSendToPeer(definition, "client"), `Channel '{channelName}' disallows client requests`)
		response = remoteFunction:InvokeServer(envelope)
	else
		assert(canSendToPeer(definition, "server"), `Channel '{channelName}' disallows server requests`)
		local targets = normalizeTargets(options and options.targets)
		assert(#targets == 1, `Channel '{channelName}' requires exactly one target for requests`)
		response = remoteFunction:InvokeClient(targets[1], envelope)
	end
	envelope.meta.tsAck = os.clock()
	self:_record("outgoing", envelope, { channel = channelName, transport = "request" })
	return response
end

function Dispatcher:intent(name: string, payload: any, options: SendOptions?)
	local channelName = ChannelRegistry.getChannelForIntent(name)
	assert(channelName, `No channel registered for intent '{name}'`)
	local definition, bundle = self:_getChannel(channelName)
	local envelope = self:_buildEnvelope(name, payload, options)
	self:_sendEvent(channelName, definition, bundle, envelope, options)
end

function Dispatcher:emit(eventName: string, payload: any, options: SendOptions?)
	local channelName = ChannelRegistry.getChannelForEvent(eventName)
	assert(channelName, `No channel registered for event '{eventName}'`)
	local definition, bundle = self:_getChannel(channelName)
	local envelope = self:_buildEnvelope(eventName, payload, options)
	self:_sendEvent(channelName, definition, bundle, envelope, options)
end

function Dispatcher:request(name: string, payload: any, options: SendOptions?): any
	local channelName = ChannelRegistry.getChannelForIntent(name)
	assert(channelName, `No channel registered for request '{name}'`)
	local definition, bundle = self:_getChannel(channelName)
	local envelope = self:_buildEnvelope(name, payload, options)
	return self:_invokeRequest(channelName, definition, bundle, envelope, options)
end

function Dispatcher:onRequest(intentName: string, handler: RequestHandler): () -> ()
	assert(type(handler) == "function", "Dispatcher:onRequest expects a function handler")
	local impl = (self :: any) :: DispatcherImpl
	local channelName = ChannelRegistry.getChannelForIntent(intentName)
	if channelName then
		((self :: any)._ensureChannel)(self, channelName)
	else
		warn(`Dispatcher:onRequest received unknown intent '{intentName}'`)
	end
	assert(
		impl._requestHandlers[intentName] == nil,
		`Dispatcher already has a request handler for intent '{intentName}'`
	)
	impl._requestHandlers[intentName] = handler
	local disconnected = false
	return function()
		if disconnected then
			return
		end
		disconnected = true
		impl._requestHandlers[intentName] = nil
	end
end

function Dispatcher:stats(): StatsType
	return (self :: DispatcherImpl)._stats
end

function Dispatcher:replayBuffer(): ReplayBufferType?
	return (self :: DispatcherImpl)._replay
end

return Dispatcher
