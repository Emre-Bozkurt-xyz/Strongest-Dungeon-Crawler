--!strict
-- Client dev-only hooks (debug logging, perf timers).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local DebugConfig = require(ReplicatedStorage.Shared.Debug.DebugConfig)
local DevTuningService = require(script.Parent.DevTuningService)

local Dev = {}
local chatConn: RBXScriptConnection? = nil
local remoteConn: RBXScriptConnection? = nil

local function setupTuneCommands()
	if chatConn then
		return
	end
	local player = Players.LocalPlayer
	chatConn = player.Chatted:Connect(function(message: string)
		if string.sub(message, 1, 5) ~= "/tune" then
			return
		end
		DevTuningService.executeCommand(message)
	end)
end

local function setupStudioConsoleBridge()
	if not RunService:IsStudio() or remoteConn then
		return
	end
	local remote = ReplicatedStorage:FindFirstChild("DevTuneRemote")
	if not (remote and remote:IsA("RemoteEvent")) then
		return
	end
	remoteConn = remote.OnClientEvent:Connect(function(rawCommand: any)
		if type(rawCommand) ~= "string" then
			return
		end
		DevTuningService.executeCommand(rawCommand)
	end)
end

local function exposeGlobals()
	local g: any = _G
	g.Tune = function(rawCommand: string)
		return DevTuningService.executeCommand(rawCommand)
	end
	g.DevTune = g.Tune
end

function Dev.start(ctx)
	DebugConfig.setMany({
		sessionPerf = false,
		projectiles = false,
		inputFlow = true,
	})

	setupTuneCommands()
	setupStudioConsoleBridge()
	exposeGlobals()
end

return Dev
