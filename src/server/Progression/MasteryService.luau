--!strict
-- MasteryService: mastery progress, earned by doing (docs/planning/progression-direction.md).
--
-- Levels and XP live in the player's save (`progression.masteries`) and are changed there directly.
-- The owning client is sent its progression -- levels, XP, and its shape selections, which the
-- mastery canvas draws together -- whenever any of it changes.
--
-- What earns mastery is provisional until the progression design pass: a basic attack landing on a
-- target counts toward the track of the weapon class it was swung with (MasteryTracks.XP_PER_HIT).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Networking = require(ReplicatedStorage.Shared.Networking)
local MasteryTracks = require(ReplicatedStorage.Shared.progression.MasteryTracks)
local BasicAttackProfileRegistry = require(ReplicatedStorage.Shared.skills.BasicAttackProfileRegistry)

local Server = ServerScriptService.Server
local PlayerDataService = require(Server.PlayerData.PlayerDataService)
local Registrar = require(Server.Services.Registrar)
local CombatService = require(Server.Services.CombatService)
local CombatLoadoutService = require(Server.Inventory.CombatLoadout.CombatLoadoutService)

type PlayerSaveData = PlayerDataService.PlayerSaveData

local dispatcher = Networking.server() :: any

local BASIC_ATTACK_SKILL = "BasicAttack"

export type LevelUp = {
	track: string,
	level: number,
}

local MasteryService = {}

local levelUpListeners: { (Player, LevelUp) -> () } = {}

local function entryOf(data: PlayerSaveData, trackId: string): { level: number, xp: number }
	local masteries = data.progression.masteries
	local entry = masteries[trackId]
	if type(entry) ~= "table" or type(entry.level) ~= "number" or type(entry.xp) ~= "number" then
		entry = { level = 0, xp = 0 }
		masteries[trackId] = entry
	end
	return entry
end

-- What the owning client is told: every track's level and XP, and its shape selections.
function MasteryService.snapshot(player: Player): { [string]: any }?
	local data = PlayerDataService.get(player)
	if not data then
		return nil
	end
	local masteries: { [string]: { level: number, xp: number } } = {}
	for _, track in ipairs(MasteryTracks.list()) do
		local entry = data.progression.masteries[track.id]
		masteries[track.id] = if type(entry) == "table"
			then { level = entry.level or 0, xp = entry.xp or 0 }
			else { level = 0, xp = 0 }
	end
	return {
		masteries = masteries,
		shapes = table.clone(data.progression.shapes),
	}
end

-- Send the player their progression. `levelUp` marks the change that caused it, for the client to
-- announce.
function MasteryService.publish(player: Player, levelUp: LevelUp?)
	local payload = MasteryService.snapshot(player)
	if not payload then
		return
	end
	payload.levelUp = levelUp
	dispatcher:emit("ProgressionUpdate", payload, { targets = { player } })
end

function MasteryService.onLevelUp(listener: (Player, LevelUp) -> ())
	table.insert(levelUpListeners, listener)
end

function MasteryService.getLevel(player: Player, trackId: string): number
	local data = PlayerDataService.get(player)
	local entry = data and data.progression.masteries[trackId]
	return if type(entry) == "table" and type(entry.level) == "number" then entry.level else 0
end

function MasteryService.grant(player: Player, trackId: string, amount: number)
	local data = PlayerDataService.get(player)
	if not data or not MasteryTracks.get(trackId) or amount <= 0 then
		return
	end
	local entry = entryOf(data, trackId)
	local startLevel = entry.level
	entry.xp += amount
	while true do
		local needed = MasteryTracks.xpToNext(entry.level)
		if not needed then
			-- At the cap there is nothing to bank XP toward.
			entry.xp = 0
			break
		end
		if entry.xp < needed then
			break
		end
		entry.xp -= needed
		entry.level += 1
	end

	if entry.level == startLevel then
		MasteryService.publish(player, nil)
		return
	end
	local levelUp: LevelUp = { track = trackId, level = entry.level }
	for _, listener in ipairs(levelUpListeners) do
		task.spawn(listener, player, levelUp)
	end
	MasteryService.publish(player, levelUp)
end

-- Set a track's level outright, XP cleared. For tooling; play earns levels through `grant`.
function MasteryService.setLevel(player: Player, trackId: string, level: number)
	local data = PlayerDataService.get(player)
	if not data or not MasteryTracks.get(trackId) then
		return
	end
	local entry = entryOf(data, trackId)
	entry.level = math.clamp(math.floor(level), 0, MasteryTracks.MAX_LEVEL)
	entry.xp = 0
	local levelUp: LevelUp = { track = trackId, level = entry.level }
	for _, listener in ipairs(levelUpListeners) do
		task.spawn(listener, player, levelUp)
	end
	MasteryService.publish(player, nil)
end

local function onHit(sourceEntityId: string, targetEntityId: string, _result: any, metadata: any)
	if sourceEntityId == targetEntityId or metadata.skillId ~= BASIC_ATTACK_SKILL then
		return
	end
	local player = Registrar.getPlayerById(sourceEntityId)
	if not player then
		return
	end
	local classKey = BasicAttackProfileRegistry.classKeyOf(CombatLoadoutService.get(sourceEntityId))
	local track = MasteryTracks.forClassKey(classKey)
	if track then
		MasteryService.grant(player, track.id, MasteryTracks.XP_PER_HIT)
	end
end

function MasteryService.start()
	CombatService.onHit(onHit)

	dispatcher:onRequest("ProgressionSnapshot", function(_payload, _meta, context)
		local player = context.player
		return if player then MasteryService.snapshot(player) else nil
	end)

	-- After the request above, which creates the channel this emits on.
	PlayerDataService.onLoaded(function(player)
		MasteryService.publish(player, nil)
	end)
end

return MasteryService
