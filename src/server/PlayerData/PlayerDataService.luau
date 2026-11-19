--!strict
-- PlayerDataService: loads, holds and releases each player's save.
--
-- ProfileStore session-locks the save, so only one server owns a player's data at a time; it
-- autosaves, and flushes every open session when the server shuts down. Without DataStore access
-- (an unpublished place, or Studio with API access off) it falls back to an in-memory store on its
-- own, so the game still runs -- nothing just persists.
--
-- Two ways state reaches the save:
--   - Services that keep their state in the save (LoadoutService) change `get(player)` directly.
--   - Services that keep their own live state (inventory, attributes) register a serializer, which
--     writes that state into the save just before every save and once more on `release`.
--
-- Keyed by player, never by entity id -- the character comes and goes, the save does not.
--
-- Sandbox (dev tooling): while a player is sandboxed, `get` returns a stand-in save instead of the
-- profile's data, and nothing is written into the profile -- not by serializers on autosave, not on
-- release. The profile keeps what it held when the sandbox was entered, so leaving the sandbox (or
-- the game) brings back exactly that. PlayerSession.reload makes each swap and rebuilds live state.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local ProfileStore = require(ServerScriptService.ServerPackages.ProfileStore)
local PlayerDataSchema = require(script.Parent.PlayerDataSchema)

export type PlayerSaveData = PlayerDataSchema.PlayerSaveData

local STORE_NAME = "PlayerData"

local PlayerDataService = {}

local store = ProfileStore.New(STORE_NAME, PlayerDataSchema.template())
local profiles: { [Player]: any } = {}
-- Stand-in saves of sandboxed players, returned by `get` in place of the profile's data.
local sandboxes: { [Player]: PlayerSaveData } = {}
local loadedHandlers: { (Player, PlayerSaveData, boolean?) -> () } = {}
local serializers: { (Player, PlayerSaveData) -> () } = {}
-- Threads waiting in waitForData, resumed with the save (or nil if the player left first).
local waiting: { [Player]: { thread } } = {}

local function profileKey(player: Player): string
	return `Player_{player.UserId}`
end

local function isInGame(player: Player): boolean
	return player.Parent == Players
end

local function resumeWaiting(player: Player, data: PlayerSaveData?)
	local threads = waiting[player]
	waiting[player] = nil
	for _, thread in ipairs(threads or {}) do
		task.spawn(thread, data)
	end
end

local function runSerializers(player: Player, data: PlayerSaveData)
	for _, serializer in ipairs(serializers) do
		local ok, err = pcall(serializer :: any, player, data)
		if not ok then
			-- One failing serializer must not stop the others, or the rest of the save goes stale.
			warn(`PlayerDataService: serializer failed for {player.Name}: {err}`)
		end
	end
end

local function loadPlayer(player: Player)
	local profile = store:StartSessionAsync(profileKey(player), {
		Cancel = function()
			return not isInGame(player)
		end,
	} :: any)

	if not profile then
		-- Cancelled because they left, or the session could not be started (another server would not
		-- release it, or DataStores are down). Playing on without a save would lose their progress.
		resumeWaiting(player, nil)
		if isInGame(player) then
			player:Kick("Your data could not be loaded. Please rejoin.")
		end
		return
	end

	profile:AddUserId(player.UserId)
	PlayerDataSchema.migrate(profile.Data)
	profile:Reconcile()

	profile.OnSave:Connect(function()
		-- Only while this server still holds live state for them. After `release` the services
		-- have been cleaned up, and serializing then would overwrite the save with empty state.
		-- While sandboxed the live state is the stand-in's, which must never reach the profile.
		if profiles[player] == profile and not sandboxes[player] then
			runSerializers(player, profile.Data :: PlayerSaveData)
		end
	end)

	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		sandboxes[player] = nil
		-- Also fires when another server takes the session over; this server must stop using it.
		if isInGame(player) then
			player:Kick("Your data was opened on another server. Please rejoin.")
		end
	end)

	if not isInGame(player) then
		resumeWaiting(player, nil)
		profile:EndSession()
		return
	end

	profiles[player] = profile
	for _, handler in ipairs(loadedHandlers) do
		task.spawn(handler, player, profile.Data :: PlayerSaveData)
	end
	resumeWaiting(player, profile.Data :: PlayerSaveData)
end

-- The player's live save, or nil until it has loaded (and after they leave). The stand-in while
-- they are sandboxed.
function PlayerDataService.get(player: Player): PlayerSaveData?
	local profile = profiles[player]
	if not profile then
		return nil
	end
	return sandboxes[player] or profile.Data :: PlayerSaveData
end

-- Yields until the player's save has loaded. Nil if they left, or it could not be loaded.
function PlayerDataService.waitForData(player: Player): PlayerSaveData?
	local data = PlayerDataService.get(player)
	if data or not isInGame(player) then
		return data
	end
	local threads = waiting[player] or {}
	waiting[player] = threads
	table.insert(threads, coroutine.running())
	return coroutine.yield()
end

-- Called when a player's save has loaded, including for players whose save loaded before the
-- handler was registered; and again, with `reloaded` true, each time PlayerSession.reload puts
-- different data in its place. A handler is therefore "the player's save is now `data`": repair
-- it, derive from it, tell the client.
function PlayerDataService.onLoaded(handler: (player: Player, data: PlayerSaveData, reloaded: boolean?) -> ())
	table.insert(loadedHandlers, handler)
	for player in pairs(profiles) do
		task.spawn(handler, player, PlayerDataService.get(player) :: PlayerSaveData, false)
	end
end

-- Run every onLoaded handler again for the data `get` now returns. For PlayerSession.reload, once
-- the live state has been rebuilt from it.
function PlayerDataService.replayLoaded(player: Player)
	local data = PlayerDataService.get(player)
	if not data then
		return
	end
	for _, handler in ipairs(loadedHandlers) do
		task.spawn(handler, player, data, true)
	end
end

-- Write live state into the save. Runs just before every save and once on `release`; must not
-- yield.
function PlayerDataService.addSerializer(serializer: (Player, PlayerSaveData) -> ())
	table.insert(serializers, serializer)
end

-- The player is leaving: capture their live state and end the session. The caller must do this
-- before any service drops that player's state.
function PlayerDataService.release(player: Player)
	resumeWaiting(player, nil)
	local profile = profiles[player]
	if not profile then
		return
	end
	if not sandboxes[player] then
		runSerializers(player, profile.Data :: PlayerSaveData)
	end
	sandboxes[player] = nil
	profiles[player] = nil
	profile:EndSession()
end

-- Make `data` what `get` returns for the player, keeping their profile as it is now; entering again
-- while sandboxed only replaces the stand-in. Only as the swap of PlayerSession.reload, which first
-- writes live state into the profile (so what they had is what they come back to) and holds back
-- every write of live state until it has been rebuilt from `data`. False when their save has not
-- loaded.
function PlayerDataService.enterSandbox(player: Player, data: PlayerSaveData): boolean
	if not profiles[player] then
		return false
	end
	sandboxes[player] = data
	return true
end

-- Go back to the profile's data, untouched since the sandbox was entered. Only as the swap of
-- PlayerSession.reload, for the same reason as enterSandbox.
function PlayerDataService.exitSandbox(player: Player)
	sandboxes[player] = nil
end

function PlayerDataService.isSandboxed(player: Player): boolean
	return sandboxes[player] ~= nil
end

function PlayerDataService.start()
	Players.PlayerAdded:Connect(loadPlayer)
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(loadPlayer, player)
	end
end

return PlayerDataService
