--!strict
-- ProgressionSync: sends a player their progression -- mastery, form selections, character XP -- as
-- one snapshot on the Progression channel, on request and whenever any of it changes.
--
-- The services that own each part register a section (`addSection`) rather than this module
-- requiring them, so mastery and character progress can both publish through it without depending
-- on each other. Changes in one frame coalesce into one update; the events that caused them (a
-- level reached) ride along for the client to announce.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Networking = require(ReplicatedStorage.Shared.Networking)

local PlayerDataService = require(ServerScriptService.Server.PlayerData.PlayerDataService)

type PlayerSaveData = PlayerDataService.PlayerSaveData

local dispatcher = Networking.server() :: any

-- Something worth announcing, sent with the update that carries it.
export type Event = {
	kind: "masteryLevel" | "characterLevel",
	-- Mastery track id, for "masteryLevel".
	track: string?,
	level: number,
	-- Attribute points granted with it, for "characterLevel".
	points: number?,
}

local ProgressionSync = {}

local sections: { [string]: (PlayerSaveData) -> any } = {}
local pending: { [Player]: { Event } } = {}

-- Register a part of the snapshot: `build` reads it from the player's save.
function ProgressionSync.addSection(name: string, build: (PlayerSaveData) -> any)
	assert(sections[name] == nil, `ProgressionSync: section '{name}' registered twice`)
	sections[name] = build
end

function ProgressionSync.snapshot(player: Player): { [string]: any }?
	local data = PlayerDataService.get(player)
	if not data then
		return nil
	end
	local out: { [string]: any } = {}
	for name, build in pairs(sections) do
		out[name] = build(data)
	end
	return out
end

-- Send the player their progression now.
function ProgressionSync.publish(player: Player, events: { Event }?)
	local payload = ProgressionSync.snapshot(player)
	if not payload then
		return
	end
	payload.events = events
	dispatcher:emit("ProgressionUpdate", payload, { targets = { player } })
end

-- Send at the end of the frame, gathering every change made until then into one update.
function ProgressionSync.schedule(player: Player, event: Event?)
	local queued = pending[player]
	if not queued then
		queued = {}
		pending[player] = queued
		task.defer(function()
			local events = pending[player]
			pending[player] = nil
			if events and player.Parent then
				ProgressionSync.publish(player, if #events > 0 then events else nil)
			end
		end)
	end
	if event then
		table.insert(queued, event)
	end
end

function ProgressionSync.start()
	dispatcher:onRequest("ProgressionSnapshot", function(_payload, _meta, context)
		local player = context.player
		return if player then ProgressionSync.snapshot(player) else nil
	end)

	-- After the request above, which creates the channel this emits on.
	PlayerDataService.onLoaded(function(player)
		ProgressionSync.publish(player, nil)
	end)
end

return ProgressionSync
