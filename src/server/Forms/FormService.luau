--!strict
-- FormService: which basic attack shape each player uses, and what they may choose
-- (docs/planning/progression-direction.md, "Forms").
--
-- A player's selection is kept per class key (a weapon class, or "unarmed") in their save, so
-- changing weapons brings back the shape last chosen for that weapon. What is unlocked is never
-- stored: it is derived from saved mastery levels each time, so changing a requirement needs no
-- save migration.
--
-- The chosen shape reaches combat through the combat loadout snapshot. This service decides it at
-- every recompute -- only a shape that fits what is held and is unlocked -- and both peers then
-- resolve the basic attack from that snapshot (BasicAttackProfileRegistry.resolve).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Networking = require(ReplicatedStorage.Shared.Networking)
local BasicAttackProfileRegistry = require(ReplicatedStorage.Shared.skills.BasicAttackProfileRegistry)
local BasicAttackProfileTypes = require(ReplicatedStorage.Shared.skills.BasicAttackProfileTypes)
local MasteryTracks = require(ReplicatedStorage.Shared.progression.MasteryTracks)

local Server = ServerScriptService.Server
local PlayerDataService = require(Server.PlayerData.PlayerDataService)
local Registrar = require(Server.Services.Registrar)
local CombatLoadoutService = require(Server.Inventory.CombatLoadout.CombatLoadoutService)
local SkillMetadataService = require(Server.SkillsFramework.SkillMetadataService)
local MasteryService = require(Server.Progression.MasteryService)

type PlayerSaveData = PlayerDataService.PlayerSaveData
type Shape = BasicAttackProfileTypes.BasicAttackProfile

local dispatcher = Networking.server() :: any

-- Selecting a shape recomputes the combat loadout; a person choosing from a menu sends a handful.
local RATE_WINDOW = 5
local RATE_MAX = 20

local FormService = {}

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

-- Track id -> level from the save, the shape the shared unlock rule (MasteryTracks.meets) reads.
function FormService.levelsOf(data: PlayerSaveData): { [string]: number }
	local levels: { [string]: number } = {}
	for track, entry in pairs(data.progression.masteries) do
		if type(entry) == "table" and type(entry.level) == "number" then
			levels[track] = entry.level
		end
	end
	return levels
end

function FormService.isUnlocked(data: PlayerSaveData, shape: Shape): boolean
	return MasteryTracks.meets(FormService.levelsOf(data), shape.requires)
end

-- The shape to write into this snapshot: the player's selection for what they hold, if it still
-- fits and is still unlocked. Nil falls back to the weapon's default.
local function selectedShape(entityId: string, snapshot: any): string?
	local player = Registrar.getPlayerById(entityId)
	local data = player and PlayerDataService.get(player)
	if not data then
		return nil
	end
	local classKey = BasicAttackProfileRegistry.classKeyOf(snapshot)
	local shapeId = data.progression.shapes[classKey]
	local shape = if shapeId then BasicAttackProfileRegistry.get(shapeId) else nil
	if shape and BasicAttackProfileRegistry.fitsClass(shape, classKey) and FormService.isUnlocked(data, shape) then
		return shapeId
	end
	return nil
end

-- Re-decide the player's shape now, e.g. after their mastery changed.
function FormService.refresh(player: Player)
	local entityId = Registrar.getPlayerId(player)
	if entityId and CombatLoadoutService.get(entityId) then
		CombatLoadoutService.recompute(entityId)
	end
end

-- Select `shapeId` for `classKey`, or "" to go back to the weapon's default.
function FormService.select(player: Player, classKey: any, shapeId: any): (boolean, string?)
	local data = PlayerDataService.get(player)
	if not data then
		return false, "not_loaded"
	end
	-- A class with no shapes at all is not one the registry knows (this also rejects junk strings).
	if type(classKey) ~= "string" or #BasicAttackProfileRegistry.shapesFor(classKey) == 0 then
		return false, "invalid_class"
	end
	if shapeId == "" then
		data.progression.shapes[classKey] = nil
		FormService.refresh(player)
		MasteryService.publish(player, nil)
		return true, nil
	end
	local shape = if type(shapeId) == "string" then BasicAttackProfileRegistry.get(shapeId) else nil
	if not shape then
		return false, "unknown_shape"
	end
	if not BasicAttackProfileRegistry.fitsClass(shape, classKey) then
		return false, "wrong_class"
	end
	if not FormService.isUnlocked(data, shape) then
		return false, "locked"
	end
	data.progression.shapes[classKey] = shape.id
	FormService.refresh(player)
	MasteryService.publish(player, nil)
	return true, nil
end

function FormService.start()
	CombatLoadoutService.setShapeSelector(selectedShape)

	-- A level change can unlock or lock the selected shape; re-deciding it applies that at once.
	MasteryService.onLevelUp(function(player)
		FormService.refresh(player)
	end)

	-- A different shape means a different cost; the client predicts affordability from metadata.
	CombatLoadoutService.onChanged(function(entityId)
		local player = Registrar.getPlayerById(entityId)
		if player then
			SkillMetadataService.updateAllSkills(player)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		rates[player] = nil
	end)

	dispatcher:onRequest("LoadoutSelectShape", function(payload, _meta, context): { ok: boolean, error: string? }
		local player = context.player
		if not player then
			return { ok = false, error = "no_player" }
		end
		if not withinRate(player) then
			return { ok = false, error = "rate_limited" }
		end
		if type(payload) ~= "table" then
			return { ok = false, error = "invalid_request" }
		end
		local ok, err = FormService.select(player, payload.classKey, payload.shapeId)
		return { ok = ok, error = err }
	end)
end

return FormService
