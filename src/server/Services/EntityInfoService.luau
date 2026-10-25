--!strict
-- EntityInfoService: what each player is told about the entities around them.
--
-- Two streams share the EntityInfo channel:
--
--   Presence (`EntityInfoDelta`, PRESENCE_RATE Hz) -- every entity within the viewer's perception
--   radius, with whatever health their PerceptionTier reveals. It decides membership, and it is the
--   backstop for health changes the vitals stream does not report (continuous regeneration).
--
--   Vitals (`EntityVitals`, once per frame) -- health for entities whose pools changed this frame,
--   sent only to viewers whose latest presence included them, at the tier that presence used. This
--   is what lets a health bar move on the frame after a hit instead of waiting out a presence tick.
--
-- Presence decides who may see what; vitals never widen it, so an entity that walks into range is
-- only reported once the next presence tick has admitted it.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = game:GetService("ServerScriptService").Server

local Networking = require(ReplicatedStorage.Shared.Networking)
local Registrar = require(Server.Services.Registrar)
local StatsManager = require(Server.Stats.StatsManager)
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)

export type EntityKind = "player" | "npc"

export type HealthReveal = {
	hpPerc: number?,
	hp: { current: number, max: number }?,
}

local EntityInfoService = {}

local dispatcher = Networking.server() :: any
dispatcher:_ensureChannel("EntityInfo")

local PRESENCE_RATE = 2
local DEFAULT_PERCEPTION_DISTANCE = 60
local HEALTH_POOL = StatTypes.PoolStats.Health

-- viewer -> entityId -> reveal tier used by that viewer's latest presence.
local viewing: { [Player]: { [string]: number } } = {}
local dirty: { [string]: true } = {}

local presenceConnection: RBXScriptConnection? = nil
local vitalsConnection: RBXScriptConnection? = nil
local disconnectPoolListener: (() -> ())? = nil
local playerRemovingConnection: RBXScriptConnection? = nil

local function rootOf(model: Model): BasePart?
	local root = model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Tier 1 reveals a fraction, tier 2 the numbers too. Nil when nothing is revealed.
local function revealHealth(entityId: string, tier: number): HealthReveal?
	if tier < 1 then
		return nil
	end
	local current = StatsManager.getPoolCurrentValue(entityId, HEALTH_POOL)
	local max = StatsManager.getPoolMaxValue(entityId, HEALTH_POOL)
	if not current or not max or max <= 0 then
		return nil
	end
	local reveal: HealthReveal = { hpPerc = math.clamp(current / max, 0, 1) }
	if tier >= 2 then
		reveal.hp = { current = current, max = max }
	end
	return reveal
end

local function perceptionOf(viewerId: string): (number, number)
	local radius = StatsManager.getStatValue(viewerId, StatTypes.StaticStats.PerceptionDistance)
		or DEFAULT_PERCEPTION_DISTANCE
	local tier = StatsManager.getStatValue(viewerId, StatTypes.StaticStats.PerceptionTier) or 0
	return radius, tier
end

type Candidate = { id: string, model: Model, root: BasePart, kind: EntityKind }

local function collectCandidates(): { Candidate }
	local candidates: { Candidate } = {}
	for _, model in ipairs(Registrar.getAllEntities()) do
		local id = Registrar.getEntityId(model)
		local root = rootOf(model)
		if id and root and model:IsDescendantOf(workspace) then
			local kind: EntityKind = if Players:GetPlayerFromCharacter(model) then "player" else "npc"
			table.insert(candidates, { id = id, model = model, root = root, kind = kind })
		end
	end
	return candidates
end

local function tickPresence(viewer: Player, candidates: { Candidate })
	local character = viewer.Character
	local viewerId = Registrar.getPlayerId(viewer)
	local viewerRoot = character and rootOf(character)
	if not viewerId or not viewerRoot then
		viewing[viewer] = nil
		return
	end

	local radius, tier = perceptionOf(viewerId)
	local center = viewerRoot.Position
	local seen: { [string]: number } = {}
	local items = {}
	for _, candidate in ipairs(candidates) do
		if candidate.model ~= character and (candidate.root.Position - center).Magnitude <= radius then
			local item: { [string]: any } = { id = candidate.id, kind = candidate.kind, name = candidate.model.Name }
			local reveal = revealHealth(candidate.id, tier)
			if reveal then
				item.hpPerc = reveal.hpPerc
				item.hp = reveal.hp
			end
			table.insert(items, item)
			seen[candidate.id] = tier
		end
	end
	viewing[viewer] = seen

	-- Sent even when empty, so the client can retire entities that left range.
	dispatcher:emit("EntityInfoDelta", { type = "presence", items = items }, {
		targets = viewer,
		qos = "BACKGROUND",
	})
end

local function flushVitals()
	if next(dirty) == nil then
		return
	end
	local changed = dirty
	dirty = {}

	for viewer, seen in pairs(viewing) do
		local items = nil
		for entityId in pairs(changed) do
			local tier = seen[entityId]
			local reveal = tier and revealHealth(entityId, tier)
			if reveal then
				items = items or {}
				table.insert(items, { id = entityId, hpPerc = reveal.hpPerc, hp = reveal.hp })
			end
		end
		if items then
			dispatcher:emit("EntityVitals", { items = items }, {
				targets = viewer,
				qos = "HIGH",
			})
		end
	end
end

function EntityInfoService.start()
	if presenceConnection then
		return
	end

	disconnectPoolListener = StatsManager.onPoolChanged(function(entityId, poolName)
		if poolName == HEALTH_POOL then
			dirty[entityId] = true
		end
	end)

	local accumulator = 0
	presenceConnection = RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < 1 / PRESENCE_RATE then
			return
		end
		accumulator = 0
		local candidates = collectCandidates()
		for _, viewer in ipairs(Players:GetPlayers()) do
			tickPresence(viewer, candidates)
		end
	end)

	vitalsConnection = RunService.Heartbeat:Connect(flushVitals)

	playerRemovingConnection = Players.PlayerRemoving:Connect(function(player)
		viewing[player] = nil
	end)
end

function EntityInfoService.stop()
	for _, connection in { presenceConnection, vitalsConnection, playerRemovingConnection } do
		(connection :: RBXScriptConnection):Disconnect()
	end
	presenceConnection = nil
	vitalsConnection = nil
	playerRemovingConnection = nil
	if disconnectPoolListener then
		disconnectPoolListener()
		disconnectPoolListener = nil
	end
	table.clear(viewing)
	table.clear(dirty)
end

return EntityInfoService
