--!strict
-- Client dev-only hooks (debug logging, perf timers).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local DebugConfig = require(ReplicatedStorage.Shared.Debug.DebugConfig)
local SkillSlots = require(script.Parent.Parent.SkillsFramework.SkillSlots)
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

local function setupSkillProfiles()
	-- Ensure at least 2 profiles for cycling during dev.
	local p1 = SkillSlots.getActiveProfileId()
	local p2 = SkillSlots.createProfile()

	-- Profile 1: core melee + traversal
	-- Phase B: BasicAttack in place of Punch -- same slot/keybind, adaptive per current weapon.
	SkillSlots.setActiveProfile(p1)
	SkillSlots.assign(1, "BasicAttack")
	SkillSlots.assign(2, "Dash")
	SkillSlots.assign(3, "DodgeRoll")

	-- Profile 2: heavier / spell skills
	SkillSlots.setActiveProfile(p2)
	SkillSlots.assign(1, "TripleStrike")
	SkillSlots.assign(2, "ManaBall")
	SkillSlots.assign(3, "CascadingManaBalls")

	-- Return to profile 1 by default.
	SkillSlots.setActiveProfile(p1)
end

function Dev.start(ctx)
	DebugConfig.setMany({
		sessionPerf = false,
		projectiles = false,
		inputFlow = true,
	})

	setupSkillProfiles()
	setupTuneCommands()
	setupStudioConsoleBridge()
	exposeGlobals()
end

return Dev
