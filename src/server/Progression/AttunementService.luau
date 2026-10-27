--!strict
-- AttunementService: which masteries each player has attuned (shared/progression/Attunement), and
-- the shrines where that is changed.
--
-- A shrine is any instance in the world tagged Attunement.SHRINE_TAG, placed by a map builder; this
-- gives each one a prompt. The prompt only opens the mastery canvas on the client, which listens for
-- it; every change comes back here as a request and is checked against the player's distance to a
-- shrine, so a client cannot attune from anywhere.
--
-- Free for now: there is no currency yet.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Networking = require(ReplicatedStorage.Shared.Networking)
local Attunement = require(ReplicatedStorage.Shared.progression.Attunement)
local CharacterXP = require(ReplicatedStorage.Shared.progression.CharacterXP)
local MasteryTracks = require(ReplicatedStorage.Shared.progression.MasteryTracks)

local Server = ServerScriptService.Server
local PlayerDataService = require(Server.PlayerData.PlayerDataService)
local ProgressionSync = require(script.Parent.ProgressionSync)

type PlayerSaveData = PlayerDataService.PlayerSaveData

local dispatcher = Networking.server() :: any

local PROMPT_NAME = "AttunementPrompt"
-- Each change recomputes the combat loadout; a person at a shrine sends a handful.
local MIN_INTERVAL = 0.25

local AttunementService = {}

local changedListeners: { (Player) -> () } = {}
local lastRequest: { [Player]: number } = {}

-- What the player has attuned in effect (Attunement.effective over their save and level).
function AttunementService.attunedOf(data: PlayerSaveData): { string }
	return Attunement.effective(data.progression.attunement, CharacterXP.levelOf(data.character.xp))
end

-- Called after a player's attunement changes.
function AttunementService.onChanged(listener: (Player) -> ())
	table.insert(changedListeners, listener)
end

local function shrinePosition(shrine: Instance): Vector3?
	if not shrine:IsDescendantOf(Workspace) then
		return nil
	end
	if shrine:IsA("Model") then
		return shrine:GetPivot().Position
	elseif shrine:IsA("BasePart") then
		return shrine.Position
	end
	return nil
end

function AttunementService.isNearShrine(player: Player): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	for _, shrine in ipairs(CollectionService:GetTagged(Attunement.SHRINE_TAG)) do
		local position = shrinePosition(shrine)
		if position and (position - root.Position).Magnitude <= Attunement.SHRINE_RANGE then
			return true
		end
	end
	return false
end

-- Attune `trackId`, or release it when `attuned` is false.
function AttunementService.set(player: Player, trackId: any, attuned: any): (boolean, string?)
	local data = PlayerDataService.get(player)
	if not data then
		return false, "not_loaded"
	end
	if type(trackId) ~= "string" or not MasteryTracks.get(trackId) or type(attuned) ~= "boolean" then
		return false, "invalid_request"
	end
	if not AttunementService.isNearShrine(player) then
		return false, "not_at_shrine"
	end
	local current = AttunementService.attunedOf(data)
	local index = table.find(current, trackId)
	if attuned == (index ~= nil) then
		return true, nil
	end
	if attuned then
		if #current >= Attunement.slotsFor(CharacterXP.levelOf(data.character.xp)) then
			return false, "no_free_slot"
		end
		table.insert(current, trackId)
	else
		table.remove(current, index)
	end
	data.progression.attunement = current
	for _, listener in ipairs(changedListeners) do
		task.spawn(listener, player)
	end
	ProgressionSync.schedule(player, nil)
	return true, nil
end

local function addPrompt(shrine: Instance)
	local host: BasePart? = if shrine:IsA("BasePart")
		then shrine
		elseif shrine:IsA("Model") then shrine.PrimaryPart or shrine:FindFirstChildWhichIsA("BasePart", true)
		else nil
	if not host or host:FindFirstChild(PROMPT_NAME) then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = PROMPT_NAME
	prompt.ActionText = "Attune"
	prompt.ObjectText = "Attunement Shrine"
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0
	-- Inside the range a request is accepted from, so a prompt that shows always works.
	prompt.MaxActivationDistance = Attunement.SHRINE_RANGE - 4
	prompt.Parent = host
end

function AttunementService.start()
	ProgressionSync.addSection("attunement", AttunementService.attunedOf)

	CollectionService:GetInstanceAddedSignal(Attunement.SHRINE_TAG):Connect(addPrompt)
	for _, shrine in ipairs(CollectionService:GetTagged(Attunement.SHRINE_TAG)) do
		addPrompt(shrine)
	end

	Players.PlayerRemoving:Connect(function(player)
		lastRequest[player] = nil
	end)

	dispatcher:onRequest("ProgressionAttune", function(payload, _meta, context): { ok: boolean, error: string? }
		local player = context.player
		if not player then
			return { ok = false, error = "no_player" }
		end
		local now = os.clock()
		if now - (lastRequest[player] or -math.huge) < MIN_INTERVAL then
			return { ok = false, error = "rate_limited" }
		end
		lastRequest[player] = now
		if type(payload) ~= "table" then
			return { ok = false, error = "invalid_request" }
		end
		local ok, err = AttunementService.set(player, payload.track, payload.attuned)
		return { ok = ok, error = err }
	end)
end

return AttunementService
