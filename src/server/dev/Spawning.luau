--!strict
-- Spawning: the only place dev tooling touches the NPC system.
--
-- What dev tooling needs from an NPC system (written for whatever system replaces today's):
--   * spawn by kind at a CFrame, with options: level / area level, rank, respawn policy, AI enabled
--     or frozen, faction / hostility, health or stat overrides, and a tag or owner so a scenario can
--     find and remove exactly what it spawned
--   * a respawned NPC keeps the tag of the one it replaces
--   * enumerate the kinds that can be spawned
--   * remove an NPC cleanly, including cancelling any respawn it has pending
--   * freeze and resume AI per NPC, or for all of them
--   * expose state for inspection: current behaviour/state, target, stats
--
-- Options the current system cannot honour are ignored with one warning per option name, so a
-- scenario written for a richer system still runs on this one. Nothing outside this file should
-- require NPCSpawner, NPCManager or NPCDeath.
--
-- `snapToGround` is handled here rather than by the NPC system: the NPC is placed at the CFrame,
-- then raised or lowered so its bounding box rests on the first surface below (or just above) that
-- point. Callers can therefore give a marker's or a player's position without knowing how tall the
-- NPC is.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

export type Options = { [string]: any }

-- JSON-safe description of one NPC, for listings.
export type Info = {
	name: string,
	kind: string,
	entityId: string?,
	tag: string?,
	dead: boolean,
	position: { number },
	health: number?,
	maxHealth: number?,
}

export type Filter = {
	tag: string?,
	kind: string?,
}

local Spawning = {}

-- Set on a spawned NPC when the spawn named a `tag`; also added as a CollectionService tag.
Spawning.TAG_ATTRIBUTE = "DevSpawnTag"

local ASSETS_ROOT_NAME = "Assets"
local PREFABS_FOLDER_NAME = "NPCPrefabs"
local KIND_ATTRIBUTE = "CharacterSpecId"
-- How far above the requested point the ground probe starts, so a marker sunk into a floor still
-- finds its top, and how far down it looks.
local GROUND_PROBE_UP = 4
local GROUND_PROBE_DOWN = 80
local GROUND_CLEARANCE = 0.05

-- Option name -> expected Lua type, for the options NPCSpawner reads straight from its settings.
local PASSED_THROUGH: { [string]: string } = {
	areaLevel = "number",
	rank = "string",
	respawnDelay = "number",
	xp = "number",
	masteryValue = "number",
}

-- Handled here, or the caller's own business, so never worth a warning.
local HANDLED_HERE: { [string]: boolean } = {
	parent = true,
	tag = true,
	snapToGround = true,
	-- A request's `count` is how many times the caller spawns it, not a property of one NPC.
	count = true,
}

local warned: { [string]: boolean } = {}
local respawnHooked = false

local function warnOnce(key: string, message: string)
	if not warned[key] then
		warned[key] = true
		warn(`[Spawning] {message}`)
	end
end

-- Required on demand: the NPC modules pull in stats and registration, which a stage that spawns
-- nothing has no reason to load.
local function npcSpawner(): any
	return require(script.Parent.Parent.NPCService.NPCSpawner)
end

local function npcManager(): any
	return require(script.Parent.Parent.NPCService.NPCManager)
end

local function npcDeath(): any
	return require(script.Parent.Parent.NPCService.NPCDeath)
end

local function prefabsFolder(): Instance?
	local assets = ReplicatedStorage:FindFirstChild(ASSETS_ROOT_NAME)
	return assets and assets:FindFirstChild(PREFABS_FOLDER_NAME)
end

local function tagOf(model: Model): string?
	local tag = model:GetAttribute(Spawning.TAG_ATTRIBUTE)
	return if type(tag) == "string" then tag else nil
end

local function setTag(model: Model, tag: string)
	model:SetAttribute(Spawning.TAG_ATTRIBUTE, tag)
	CollectionService:AddTag(model, tag)
end

-- The respawn of a tagged NPC is still that spawn's: carry the tag over so whoever spawned it can
-- find and remove it.
local function hookRespawns()
	if respawnHooked then
		return
	end
	respawnHooked = true
	npcDeath().onRespawn(function(previous: Model, model: Model)
		local tag = tagOf(previous)
		if tag then
			setTag(model, tag)
		end
	end)
end

function Spawning.kinds(): { string }
	local kinds: { string } = {}
	local folder = prefabsFolder()
	if folder then
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("Model") or child:IsA("Folder") then
				table.insert(kinds, child.Name)
			end
		end
	end
	table.sort(kinds)
	return kinds
end

function Spawning.kindOf(model: Model): string
	local kind = model:GetAttribute(KIND_ATTRIBUTE)
	return if type(kind) == "string" then kind else model.Name
end

local function snapToGround(model: Model)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local excluded: { Instance } = { model }
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(excluded, player.Character)
		end
	end
	for other in pairs(npcManager().getAllNPCs() :: { [Model]: any }) do
		table.insert(excluded, other)
	end
	local drops = Workspace:FindFirstChild("ItemDrops")
	if drops then
		table.insert(excluded, drops)
	end
	params.FilterDescendantsInstances = excluded

	local pivot = model:GetPivot()
	local hit = Workspace:Raycast(
		pivot.Position + Vector3.new(0, GROUND_PROBE_UP, 0),
		Vector3.new(0, -(GROUND_PROBE_UP + GROUND_PROBE_DOWN), 0),
		params
	)
	if not hit then
		return
	end
	local boxCFrame, boxSize = model:GetBoundingBox()
	local bottom = boxCFrame.Position.Y - boxSize.Y / 2
	local lift = hit.Position.Y + GROUND_CLEARANCE - bottom
	if math.abs(lift) < 1e-3 then
		return
	end
	model:PivotTo(pivot + Vector3.new(0, lift, 0))
	-- NPCSpawner recorded where to respawn before the lift; a respawn should stand where this one does.
	if typeof(model:GetAttribute("SpawnCFrame")) == "CFrame" then
		model:SetAttribute("SpawnCFrame", model:GetPivot())
	end
end

function Spawning.npc(kind: string, cframe: CFrame, options: Options?): (Model?, string?)
	if not table.find(Spawning.kinds(), kind) then
		return nil, `Unknown NPC kind "{kind}" ({table.concat(Spawning.kinds(), ", ")})`
	end
	hookRespawns()

	local settings: { [string]: any } = { cframe = cframe }
	local tag: string? = nil
	local snap = false
	for key, value in pairs(options or {}) do
		local expected = PASSED_THROUGH[key]
		if expected then
			if type(value) == expected then
				settings[key] = value
			else
				warnOnce(`type:{key}`, `option '{key}' expects a {expected}; ignored`)
			end
		elseif key == "parent" then
			if typeof(value) == "Instance" then
				settings.parent = value
			end
		elseif key == "tag" then
			if type(value) == "string" and value ~= "" then
				tag = value
			end
		elseif key == "snapToGround" then
			snap = value == true
		elseif not HANDLED_HERE[key] then
			warnOnce(key, `NPC option '{key}' is not supported by the current NPC system; ignored`)
		end
	end

	local model = npcSpawner().spawn(kind, settings) :: Model?
	if not model then
		return nil, `NPCSpawner could not spawn "{kind}"`
	end
	if snap then
		snapToGround(model)
	end
	if tag then
		setTag(model, tag)
	end
	return model, nil
end

local function matches(model: Model, filter: Filter?): boolean
	if not filter then
		return true
	end
	if filter.tag ~= nil and tagOf(model) ~= filter.tag then
		return false
	end
	if filter.kind ~= nil and string.lower(Spawning.kindOf(model)) ~= string.lower(filter.kind) then
		return false
	end
	return true
end

-- Live NPCs, optionally only those spawned with the given `tag`.
function Spawning.all(tag: string?): { Model }
	local result: { Model } = {}
	for model in pairs(npcManager().getAllNPCs() :: { [Model]: any }) do
		if
			model.Parent
			and model:GetAttribute("Dead") ~= true
			and (tag == nil or tagOf(model) == tag)
		then
			table.insert(result, model)
		end
	end
	return result
end

-- Every registered NPC matching the filter, dying ones included, as data.
function Spawning.list(filter: Filter?): { Info }
	local statsManager = require(script.Parent.Parent.Stats.StatsManager) :: any
	local registrar = require(script.Parent.Parent.Services.Registrar) :: any
	local result: { Info } = {}
	for model in pairs(npcManager().getAllNPCs() :: { [Model]: any }) do
		if model.Parent and matches(model, filter) then
			local entityId = registrar.getEntityId(model)
			local position = model:GetPivot().Position
			table.insert(result, {
				name = model.Name,
				kind = Spawning.kindOf(model),
				entityId = entityId,
				tag = tagOf(model),
				dead = model:GetAttribute("Dead") == true,
				position = { math.floor(position.X * 10) / 10, math.floor(position.Y * 10) / 10, math.floor(position.Z * 10) / 10 },
				health = if entityId then statsManager.getPoolCurrentValue(entityId, "Health") else nil,
				maxHealth = if entityId then statsManager.getPoolMaxValue(entityId, "Health") else nil,
			})
		end
	end
	table.sort(result, function(a, b)
		if a.kind ~= b.kind then
			return a.kind < b.kind
		end
		return (a.entityId or "") < (b.entityId or "")
	end)
	return result
end

-- Removes the NPC now, and calls off any respawn it has pending. Its status effects end first:
-- unregistering does not stop them, and a burn left ticking would act on stats that are gone.
function Spawning.despawn(model: Model)
	npcDeath().cancelRespawn(model)
	local registrar = require(script.Parent.Parent.Services.Registrar) :: any
	local entityId = registrar.getEntityId(model)
	if entityId then
		local statusEffects = require(script.Parent.Parent.StatusEffects.StatusEffectsService) :: any
		statusEffects.clearAll(entityId)
	end
	npcManager().unregister(model)
	model:Destroy()
end

-- Removes every NPC matching the filter (nil: every NPC), living or dying, and calls off the pending
-- respawns of matching NPCs whose bodies are already gone. Returns how many NPCs were removed and
-- how many pending respawns were called off.
function Spawning.removeAll(filter: Filter?): (number, number)
	local removed = 0
	local cancelled = 0
	local models: { Model } = {}
	for model in pairs(npcManager().getAllNPCs() :: { [Model]: any }) do
		if matches(model, filter) then
			table.insert(models, model)
		end
	end
	for _, model in ipairs(models) do
		Spawning.despawn(model)
		removed += 1
	end
	local death = npcDeath()
	for _, model in ipairs(death.pendingRespawns() :: { Model }) do
		if matches(model, filter) and death.cancelRespawn(model) then
			cancelled += 1
		end
	end
	return removed, cancelled
end

return Spawning
