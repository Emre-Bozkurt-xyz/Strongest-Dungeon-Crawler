--!strict
-- Central SkillsEvent helper backed by the custom dispatcher (high priority, non-batchable)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Networking = require(ReplicatedStorage.Shared.Networking)

local SKILLS_CHANNEL_NAME = "Skills"
local dispatcher = Networking.server()
local dispatcherAny = dispatcher :: any
dispatcherAny:_ensureChannel(SKILLS_CHANNEL_NAME)

local DEFAULT_QOS = "CRITICAL"

local SkillsEvent = {}

function SkillsEvent:FireAllClients(payload: any)
	dispatcherAny:emit("SkillsEvent", payload, {
		qos = DEFAULT_QOS,
	})
end

function SkillsEvent:FireClient(player, payload: any)
	dispatcherAny:emit("SkillsEvent", payload, {
		targets = player,
		qos = DEFAULT_QOS,
	})
end

return SkillsEvent
