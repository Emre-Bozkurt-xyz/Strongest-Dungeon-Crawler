--!strict
-- CharacterService: the character level stream (docs/planning/progression-direction.md,
-- "Experience"), separate from mastery.
--
-- Total XP lives in the save (`character.xp`); the level is derived from it (CharacterXP). Each
-- level gained grants attribute points. Progress reaches the owning client through ProgressionSync
-- as its "character" section.
--
-- Sources so far: killing an NPC. Its XP value is shared by contribution -- each player gets the
-- share of the NPC's health they removed -- so a player who tagged a monster once gets almost
-- nothing, which is what keeps carrying from breaking progression. Quests, bounties, looting and
-- discovery grant through `grant` once they exist.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CharacterXP = require(ReplicatedStorage.Shared.progression.CharacterXP)

local Server = ServerScriptService.Server
local PlayerDataService = require(Server.PlayerData.PlayerDataService)
local Registrar = require(Server.Services.Registrar)
local CombatService = require(Server.Services.CombatService)
local AttributesManager = require(Server.Stats.AttributesManager)
local NPCDeath = require(Server.NPCService.NPCDeath)
local ProgressionSync = require(script.Parent.ProgressionSync)

local CharacterService = {}

-- NPC entity id -> player -> health they removed from it.
local contributions: { [string]: { [Player]: number } } = {}

local function xpOf(player: Player): number?
	local data = PlayerDataService.get(player)
	local character = data and data.character
	return if character and type(character.xp) == "number" then character.xp else nil
end

function CharacterService.getLevel(player: Player): number
	return CharacterXP.levelOf(xpOf(player) or 0)
end

-- Add character XP. Levels gained grant their attribute points and are announced.
function CharacterService.grant(player: Player, amount: number)
	local data = PlayerDataService.get(player)
	if not data or amount <= 0 then
		return
	end
	local before = CharacterXP.levelOf(data.character.xp)
	data.character.xp += amount
	local after = CharacterXP.levelOf(data.character.xp)
	if after <= before then
		ProgressionSync.schedule(player, nil)
		return
	end
	local points = (after - before) * CharacterXP.POINTS_PER_LEVEL
	AttributesManager.addAvailableAttributePoints(player, points)
	ProgressionSync.schedule(player, { kind = "characterLevel", level = after, points = points })
end

local function onHit(sourceEntityId: string, targetEntityId: string, result: any, _metadata: any)
	local removed = result.healthRemoved
	if type(removed) ~= "number" or removed <= 0 or Registrar.isPlayerEntity(targetEntityId) then
		return
	end
	local player = Registrar.getPlayerById(sourceEntityId)
	local target = Registrar.getEntityById(targetEntityId)
	-- Only what a kill pays for is tracked; a training dummy never dies, and would only accumulate.
	if not player or not target or type(target:GetAttribute("XPValue")) ~= "number" then
		return
	end
	local byPlayer = contributions[targetEntityId]
	if not byPlayer then
		byPlayer = {}
		contributions[targetEntityId] = byPlayer
	end
	byPlayer[player] = (byPlayer[player] or 0) + removed
end

local function onDeath(entityId: string, model: Model)
	local byPlayer = contributions[entityId]
	contributions[entityId] = nil
	local value = model:GetAttribute("XPValue")
	if not byPlayer or type(value) ~= "number" or value <= 0 then
		return
	end
	local total = 0
	for _, amount in pairs(byPlayer) do
		total += amount
	end
	if total <= 0 then
		return
	end
	for player, amount in pairs(byPlayer) do
		if player.Parent then
			CharacterService.grant(player, value * amount / total)
		end
	end
end

function CharacterService.start()
	CombatService.onHit(onHit)
	NPCDeath.onDeath(onDeath)

	ProgressionSync.addSection("character", function(data)
		return { xp = data.character.xp }
	end)
end

return CharacterService
