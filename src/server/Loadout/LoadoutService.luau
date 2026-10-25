--!strict
-- LoadoutService: the player's skill slot sets, owned by the server and kept in their save.
--
-- The client mirrors this (SkillSlots) and applies its own commands immediately, so changing a slot
-- or cycling sets mid-fight responds at once. The server applies each command with the same rules
-- (LoadoutRules), adds the checks only it can make, and answers with the authoritative loadout,
-- which the client adopts.
--
-- Commands travel as requests rather than events so each one is answered with the loadout the client
-- should now hold.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Networking = require(ReplicatedStorage.Shared.Networking)
local LoadoutTypes = require(ReplicatedStorage.Shared.skills.LoadoutTypes)
local LoadoutRules = require(ReplicatedStorage.Shared.skills.LoadoutRules)

local Server = ServerScriptService.Server
local PlayerDataService = require(Server.PlayerData.PlayerDataService)
local PlayerDataSchema = require(Server.PlayerData.PlayerDataSchema)
local SkillsManager = require(Server.SkillsFramework.SkillsManager)
local Registrar = require(Server.Services.Registrar)

local dispatcher = Networking.server() :: any

-- Generous for a person clicking through a menu or cycling sets; a client sending more is not.
local RATE_WINDOW = 5
local RATE_MAX = 40

local LoadoutService = {}

local rates: { [Player]: { windowStart: number, count: number } } = {}

local function withinRate(player: Player): boolean
	local now = os.clock()
	local rate = rates[player]
	if not rate or now - rate.windowStart >= RATE_WINDOW then
		rates[player] = { windowStart = now, count = 1 }
		return true
	end
	rate.count += 1
	return rate.count <= RATE_MAX
end

local function loadoutOf(player: Player): LoadoutTypes.Loadout?
	local data = PlayerDataService.get(player)
	return data and data.loadout
end

-- The player has the skill right now. Slots keep a skill the player loses (a weapon that granted it
-- was unequipped), but only a skill they have can be put into one.
local function ownsSkill(player: Player, skillName: string): boolean
	local entityId = Registrar.getPlayerId(player)
	return entityId ~= nil and SkillsManager.getSkill(entityId, skillName) ~= nil
end

local function handleCommand(player: Player, command: any): LoadoutTypes.LoadoutResponse
	local loadout = loadoutOf(player)
	if not loadout then
		return { ok = false, error = "not_loaded" }
	end
	if not withinRate(player) then
		return { ok = false, error = "rate_limited", loadout = loadout }
	end
	if type(command) == "table" and command.kind == "assign" then
		if type(command.skill) ~= "string" or not ownsSkill(player, command.skill) then
			return { ok = false, error = "skill_not_owned", loadout = loadout }
		end
	end
	local ok, err = LoadoutRules.apply(loadout, command)
	return { ok = ok, error = err, loadout = loadout }
end

function LoadoutService.start()
	Players.PlayerRemoving:Connect(function(player)
		rates[player] = nil
	end)

	dispatcher:onRequest("LoadoutSnapshot", function(_payload, _meta, context)
		local player = context.player
		return if player then loadoutOf(player) else nil
	end)

	dispatcher:onRequest("LoadoutCommand", function(payload, _meta, context): LoadoutTypes.LoadoutResponse
		local player = context.player
		if not player then
			return { ok = false, error = "no_player" }
		end
		return handleCommand(player, payload)
	end)

	-- Registered after the requests above, which are what create the channel this emits on; saves
	-- that loaded before start() are handled immediately.
	PlayerDataService.onLoaded(function(player, data)
		-- A save is outside data: repair it before anything reads it, falling back to the starting
		-- kit only when nothing usable is there.
		data.loadout = LoadoutRules.sanitize(data.loadout) or PlayerDataSchema.defaultLoadout()
		-- The client may have asked before the save loaded and been told nothing yet.
		dispatcher:emit("LoadoutUpdate", { loadout = data.loadout }, { targets = { player } })
	end)
end

return LoadoutService
