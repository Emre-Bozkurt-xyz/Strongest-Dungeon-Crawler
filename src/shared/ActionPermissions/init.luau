--!strict
-- ActionPermissions service - Query layer for checking if entities can perform actions
-- Follows Networking service pattern with .server() and .client() endpoints

local RunService = game:GetService("RunService")

local ActionPermissions = {}

ActionPermissions.Types = require(script.Types)

local serverSingleton = nil
local clientSingleton = nil

-- Get or create server instance
function ActionPermissions.server()
	if serverSingleton == nil then
		local Server = require(script.Server)
		serverSingleton = Server.new()
	end
	return serverSingleton
end

-- Get or create client instance
function ActionPermissions.client(sessionMirror: any?)
	if clientSingleton == nil then
		local Client = require(script.Client)
		clientSingleton = Client.new(sessionMirror)
	elseif sessionMirror and clientSingleton.setSessionMirror then
		clientSingleton:setSessionMirror(sessionMirror)
	end
	return clientSingleton
end

return ActionPermissions
