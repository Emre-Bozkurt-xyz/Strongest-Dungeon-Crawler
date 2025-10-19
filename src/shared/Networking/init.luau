--!strict
-- Shared entrypoint exposing client/server helpers for the networking layer.

local Networking = {}

Networking.Client = require(script.Client)
Networking.Server = require(script.Server)
Networking.Dispatcher = require(script.Dispatcher)
Networking.Envelope = require(script.Envelope)
Networking.ChannelRegistry = require(script.ChannelRegistry)
Networking.Stats = require(script.Stats)
Networking.ReplayBuffer = require(script.ReplayBuffer)

local clientSingleton = nil
local serverSingleton = nil

function Networking.init(config: { [string]: any })
	assert(type(config) == "table", "Networking.init expects a config table")
	assert(config.peer == "client" or config.peer == "server", "Networking.init requires 'peer' to be 'client' or 'server'")
	if config.peer == "client" then
		return Networking.Client(config)
	else
		return Networking.Server(config)
	end
end

function Networking.client(config: { [string]: any }?)
	if clientSingleton == nil then
		clientSingleton = Networking.Client(config)
	else
		if config ~= nil then
			warn("Networking.client ignoring config on subsequent call; singleton already created")
		end
	end
	return clientSingleton
end

function Networking.server(config: { [string]: any }?)
	if serverSingleton == nil then
		serverSingleton = Networking.Server(config)
	else
		if config ~= nil then
			warn("Networking.server ignoring config on subsequent call; singleton already created")
		end
	end
	return serverSingleton
end

return Networking
