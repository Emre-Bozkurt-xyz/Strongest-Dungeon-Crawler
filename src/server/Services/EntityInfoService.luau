-- EntityInfoService: Server-authoritative identities and info deltas for entities (players + NPCs)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Server = game:GetService("ServerScriptService").Server

local Networking = require(ReplicatedStorage.Shared.Networking)
local Registrar = require(Server.Services.Registrar)
local NPCManager = require(Server.NPCService.NPCManager)
local StatsManager = require(Server.Stats.StatsManager)
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)

export type EntityKind = "player" | "npc"

local EntityInfoService = {}

local ENTITYINFO_CHANNEL_NAME = "EntityInfo"
local dispatcher = Networking.server()
local dispatcherAny = dispatcher :: any
dispatcherAny:_ensureChannel(ENTITYINFO_CHANNEL_NAME)

-- Identity registry
local idByEntity: { [Instance]: string } = {}
local entityById: { [string]: Instance } = {}

local TICK_RATE = 2 -- Hz per player
local _accum = 0
local DEBUG_ENTITY_INFO = false -- set true to enable sample logs
local _debugNextLogAt = 0.0

local function isAliveModel(mdl: Model?): boolean
	if not mdl or not mdl.Parent then
		return false
	end
	if not mdl:FindFirstAncestorOfClass(Workspace) then
		return false
	end
	local hrp = mdl:FindFirstChild("HumanoidRootPart")
	return hrp ~= nil
end

local function getKindForEntity(ent: Instance): EntityKind
	local m: Model? = ent:IsA("Model") and ent or ent:FindFirstAncestorOfClass("Model")
	if not m then
		return "npc"
	end
	local player = Players:GetPlayerFromCharacter(m)
	if player then
		return "player"
	else
		return "npc"
	end
end

local function collectEntities(): { Model }
	local results: { Model } = {}
	local entities = Registrar.getAllEntities()
	for _, entity in ipairs(entities) do
		if isAliveModel(entity) then
			table.insert(results, entity)
		end
	end
	return results
end

local function sqrDist(a: Vector3, b: Vector3): number
	local dx = a.X - b.X
	local dy = a.Y - b.Y
	local dz = a.Z - b.Z
	return dx * dx + dy * dy + dz * dz
end

local function buildPresenceRecord(model: Model)
	local id = Registrar.getEntityId(model)
	local hrp = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local kind = getKindForEntity(model)
	return {
		id = id,
		kind = kind,
		name = model.Name,
		pos = hrp and hrp.Position or Vector3.zero,
	}
end

-- Compute HP details for a model if stats are registered
local function getHpDetails(entityId: string): (number?, number?, number?)
	local model = Registrar.getEntityById(entityId)
	if not model then
		return nil, nil, nil
	end
	local cur = StatsManager.getPoolCurrentValue(entityId, StatTypes.PoolStats.Health)
	local max = StatsManager.getPoolMaxValue(entityId, StatTypes.PoolStats.Health)

	if not cur and not max then
		return nil, nil, nil
	end

	local perc = math.clamp(cur / max, 0, 1)
	return cur, max, perc
end

-- Determine what details to reveal to a viewer about a model, based on Perception and distance
local function applyReveal(
	_viewer: Player,
	entityId: string,
	_modelHrp: BasePart,
	_dist2: number,
	item: any,
	tier: number
)
	local cur: number?, max: number?, perc: number? = getHpDetails(entityId)
	if not perc then
		return
	end
	-- Tier policy:
	--  - tier >= 1: reveal hpPerc
	--  - tier >= 2: reveal numeric hp too
	if tier >= 1 then
		item.hpPerc = perc
	end
	if tier >= 2 and cur and max then
		item.hp = { current = cur, max = max }
	end
end

local function tickPlayer(player: Player)
	local char = player.Character
	if not char or not isAliveModel(char) then
		return
	end
	local hrp = (char :: Model):FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end

	local entityId = Registrar.getPlayerId(player)

	local center = hrp.Position
	local radius = (StatsManager.getStatValue(entityId, StatTypes.StaticStats.PerceptionDistance) or 60)
	local r2 = radius * radius
	local tier = (StatsManager.getStatValue(entityId, StatTypes.StaticStats.PerceptionTier) or 0)
	local items = {}
	for _, m in ipairs(collectEntities()) do
		if m ~= char then
			local mhrp = m:FindFirstChild("HumanoidRootPart") :: BasePart?
			if mhrp and sqrDist(center, mhrp.Position) <= r2 then
				local item = buildPresenceRecord(m)
				applyReveal(player, m, mhrp, sqrDist(center, mhrp.Position), item, tier)
				table.insert(items, item)
			end
		end
	end

	-- Always send presence payload (even when empty) so clients can handle hide/destroy when out of range
	dispatcherAny:emit("EntityInfoDelta", {
		type = "presence",
		items = items,
		ts = os.clock(),
	}, {
		targets = player,
		qos = "BACKGROUND",
	})
	-- Optional sample debug print (throttled to ~1/sec). Only prints details when we have at least one item.
	if DEBUG_ENTITY_INFO and #items > 0 then
		local now = os.clock()
		if now >= _debugNextLogAt then
			_debugNextLogAt = now + 1.0
			local first = items[1]
			local extra = ""
			local fAny = first :: any
			if fAny.hpPerc then
				extra = string.format(" hp%%=%.0f%%", (fAny.hpPerc :: number) * 100)
			end
			if fAny.hp then
				local hp = fAny.hp :: any
				extra ..= string.format(" hp=%d/%d", hp.current, hp.max)
			end
			print(
				string.format(
					"[EntityInfo] -> %s: %d nearby, first=%s(%s)%s",
					player.Name,
					#items,
					first.name,
					first.kind,
					extra
				)
			)
		end
	end
end

local _conn: RBXScriptConnection? = nil
function EntityInfoService.start()
	if _conn then
		return
	end
	_accum = 0
	_conn = RunService.Heartbeat:Connect(function(dt)
		_accum += dt
		if _accum >= (1 / TICK_RATE) then
			_accum = 0
			for _, plr in ipairs(Players:GetPlayers()) do
				tickPlayer(plr)
			end
		end
	end)

	-- Handle on-demand info requests (Phase 2: return minimal info; HP reveal comes later)
	dispatcherAny:onRequest("EntityInfoRequest", function(payload, _meta, context)
		local player = context.player
		if not player then
			warn("EntityInfoService received EntityInfoRequest without player context")
			return { ok = false, error = "no_player" }
		end
		local playerId = Registrar.getPlayerId(player)

		local id = payload and payload.id
		if type(id) ~= "string" then
			return { ok = false, error = "bad_id" }
		end
		local model = Registrar.getEntityById(id)
		if not model or not model:IsDescendantOf(game) then
			return { ok = false, error = "not_found" }
		end
		-- Basic presence payload
		local kind = getKindForEntity(model)
		local hrp = model and (model:FindFirstChild("HumanoidRootPart") :: BasePart?)
		local res = {
			ok = true,
			error = "",
			id = id,
			kind = kind,
			name = model and model.Name or tostring(model),
			pos = hrp and hrp.Position or Vector3.zero,
		}
		-- Apply the same reveal policy for the requester
		if player and model and hrp then
			local vPlayer = player :: Player
			local vChar = vPlayer.Character
			if vChar then
				local vHrp = vChar:FindFirstChild("HumanoidRootPart") :: BasePart?
				if vHrp then
					local radius2 = (
						StatsManager.getStatValue(playerId, StatTypes.StaticStats.PerceptionDistance) or 60
					)
					radius2 *= radius2
					local tier2 = (StatsManager.getStatValue(playerId, StatTypes.StaticStats.PerceptionTier) or 0)
					if sqrDist(vHrp.Position, (hrp :: BasePart).Position) <= radius2 then
						applyReveal(vPlayer, id, hrp :: BasePart, 0, res, tier2)
					end
				end
			end
		end
		if DEBUG_ENTITY_INFO then
			local extra = ""
			if (res :: any).hpPerc then
				extra = string.format(" hp%%=%.0f%%", ((res :: any).hpPerc :: number) * 100)
			end
			if (res :: any).hp then
				local hp2 = (res :: any).hp
				extra ..= string.format(" hp=%d/%d", hp2.current, hp2.max)
			end
			print(
				string.format("[EntityInfo][REQ] %s -> id=%s %s(%s)%s", player.Name, res.id, res.name, res.kind, extra)
			)
		end
		return res
	end)
end

function EntityInfoService.stop()
	if _conn then
		_conn:Disconnect()
		_conn = nil
	end
end

return EntityInfoService
