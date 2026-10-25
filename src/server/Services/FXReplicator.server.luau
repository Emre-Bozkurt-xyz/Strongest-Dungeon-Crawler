-- FXReplicator: relays the effects and sounds a client plays for its own character to the other
-- players near it. The sender has already played them locally, so it is never sent its own back.
--
-- Payloads come from clients and are relayed, not acted on, but the caster is always the sender's
-- own entity: a client cannot make effects appear on someone else's character.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Server = game:GetService("ServerScriptService").Server

local Networking = require(ReplicatedStorage.Shared.Networking)
local Registrar = require(Server.Services.Registrar)

local dispatcher = Networking.server()
dispatcher:_ensureChannel("FX")

local DEFAULT_RANGE = 50
local MAX_RANGE = 200

local function senderOf(meta: any): Player?
	local userId = meta and meta.playerId
	return if type(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
end

local function rootPosition(model: Model?): Vector3?
	local root = model and model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function othersInRange(sender: Player, position: Vector3, range: number): { Player }
	local audience = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local playerPosition = player ~= sender and rootPosition(player.Character)
		if playerPosition and (playerPosition - position).Magnitude <= range then
			table.insert(audience, player)
		end
	end
	return audience
end

local function relay(eventName: string, payload: any, meta: any)
	local sender = senderOf(meta)
	if not sender or type(payload) ~= "table" then
		return
	end
	local entityId = Registrar.getPlayerId(sender)
	local origin = if typeof(payload.position) == "Vector3"
		then payload.position
		elseif typeof(payload.origin) == "Vector3" then payload.origin
		else rootPosition(sender.Character)
	if not entityId or not origin then
		return
	end
	payload.entityId = entityId
	local range = if type(payload.range) == "number" then math.clamp(payload.range, 0, MAX_RANGE) else DEFAULT_RANGE
	dispatcher:emit(eventName, payload, {
		targets = othersInRange(sender, origin, range),
	})
end

dispatcher:on("FXEvent", function(payload, meta)
	relay("FXEvent", payload, meta)
end)

dispatcher:on("SFXEvent", function(payload, meta)
	if type(payload) == "table" and type(payload.soundId) == "string" then
		relay("SFXEvent", payload, meta)
	end
end)
