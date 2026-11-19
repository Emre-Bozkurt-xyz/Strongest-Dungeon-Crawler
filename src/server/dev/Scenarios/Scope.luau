--!strict
-- Scope: what a scenario's `setup` is handed (`s`), and the record of everything the scenario made,
-- so that tearing it down removes exactly that: its NPCs (found by the scenario spawn tag, dying ones
-- and pending respawns included), timers, tracked instances, cleanup callbacks, loot dropped in the
-- world while it ran, and the server debug flags it changed.
--
-- Loot is the exception to "removes": a drop is a real item when it belongs to a real save
-- (Characters.dropOrigin), and destroying it would delete it from that save. Such drops go back
-- into the owner's bag at teardown, or stay in the world when that cannot be done (bag full, owner
-- now on a character preset, whose bag is thrown away) and go back at a later teardown once it can.
-- Only drops belonging to a stand-in save, or to no one, are removed.
--
-- Errors raised by the API (a missing marker, an unknown NPC kind, a failed command) carry no
-- position, because they are read as "the scenario is wrong", not as a bug in this module.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local DebugConfig = require(ReplicatedStorage.Shared.Debug.DebugConfig)

local devFolder = script.Parent.Parent
local Stages = require(devFolder.Stages)
local Spawning = require(devFolder.Spawning)
local Characters = require(devFolder.Characters)

local Server = ServerScriptService.Server

export type Where = string | CFrame | Vector3

export type RowOptions = {
	spacing: number?,
	options: Spawning.Options?,
}

export type Scope = {
	id: string,
	player: Player?,
	players: { Player },
	stage: Stages.Stage?,
	-- Where the scenario's instances go: the stage folder, or a folder of its own in the world.
	folder: Instance,
	marker: (name: string) -> CFrame,
	markers: (name: string) -> { CFrame },
	spawn: (kind: string, where: Where, options: Spawning.Options?) -> Model,
	spawnRow: (kind: string, count: number, where: Where, row: RowOptions?) -> { Model },
	spawned: (kind: string?) -> { Model },
	status: (target: any, effectId: string, params: any?) -> number,
	give: (itemId: string, count: number?, meta: { [string]: any }?) -> (),
	run: (text: string) -> any,
	after: (seconds: number, fn: () -> ()) -> (),
	every: (seconds: number, fn: () -> ()) -> (),
	track: (instance: Instance) -> Instance,
	onCleanup: (fn: () -> ()) -> (),
}

export type Handle = {
	scope: Scope,
	tag: string,
	closed: boolean,
	threads: { thread },
	cleanups: { () -> () },
	tracked: { Instance },
	ownsFolder: boolean,
	lootBefore: { [string]: boolean },
	flagsBefore: { [string]: boolean },
}

export type Params = {
	id: string,
	player: Player?,
	stage: Stages.Stage?,
	folder: Instance,
	ownsFolder: boolean,
	tag: string,
}

local LOOT_TAG = "LootDrop"
local DEFAULT_ROW_SPACING = 5

local ScopeModule = {}

-- Real-save drops a teardown could not hand back (bag full, owner on a preset), by item uid. They
-- outlive the scope that saw them, since the next scope counts them as loot it found in place.
local stranded: { [string]: Player } = {}

local function fail(message: string): never
	error(message, 0)
end

local function lootUids(): { [string]: boolean }
	local uids: { [string]: boolean } = {}
	for _, drop in ipairs(CollectionService:GetTagged(LOOT_TAG)) do
		local uid = drop:GetAttribute("ItemUid")
		if type(uid) == "string" then
			uids[uid] = true
		end
	end
	return uids
end

local function listOrNone(names: { string }): string
	return if #names > 0 then table.concat(names, ", ") else "none"
end

local function missingMarker(stage: Stages.Stage?, name: string): never
	local stageNames = if stage then listOrNone(stage:markerNames()) else "no stage loaded"
	fail(`no marker named '{name}' (stage markers: {stageNames}; world markers: {listOrNone(Stages.worldMarkerNames())})`)
end

-- Spreads `count` positions along the CFrame's right vector, centred on it.
function ScopeModule.row(center: CFrame, count: number, spacing: number): { CFrame }
	local result: { CFrame } = {}
	for index = 1, count do
		local offset = (index - (count + 1) / 2) * spacing
		table.insert(result, center + center.RightVector * offset)
	end
	return result
end

local function entityOf(model: Model): string?
	local registrar = require(Server.Services.Registrar) :: any
	return registrar.getEntityId(model)
end

local function isSandboxed(player: Player): boolean
	local playerData = require(Server.PlayerData.PlayerDataService) :: any
	return playerData.isSandboxed(player)
end

-- True when the drop went back into its owner's real bag.
local function returnToOwner(owner: Player?, uid: string): boolean
	if not owner or owner.Parent ~= Players or isSandboxed(owner) then
		return false
	end
	local registrar = require(Server.Services.Registrar) :: any
	local inventory = require(Server.Inventory.InventoryService) :: any
	local entityId = registrar.getPlayerId(owner)
	if not entityId then
		return false
	end
	local ok = inventory.addExistingItem(entityId, uid)
	return ok == true
end

function ScopeModule.new(params: Params): Handle
	local handle: Handle = {
		scope = nil :: any,
		tag = params.tag,
		closed = false,
		threads = {},
		cleanups = {},
		tracked = {},
		ownsFolder = params.ownsFolder,
		lootBefore = lootUids(),
		flagsBefore = {},
	}
	local stage = params.stage

	local function guarded(label: string, fn: () -> ())
		if handle.closed then
			return
		end
		local ok, err = xpcall(fn, debug.traceback)
		if not ok then
			warn(`[Scenarios] {params.id}: {label} failed: {err}`)
		end
	end

	local function marker(name: string): CFrame
		local found = (stage and stage:marker(name)) or Stages.worldMarker(name)
		if not found then
			missingMarker(stage, name)
		end
		return found :: CFrame
	end

	local function markers(name: string): { CFrame }
		local found = if stage then stage:markers(name) else {}
		if #found == 0 then
			found = Stages.worldMarkers(name)
		end
		if #found == 0 then
			missingMarker(stage, name)
		end
		return found
	end

	local function resolveWhere(where: Where): CFrame
		if typeof(where) == "CFrame" then
			return where :: CFrame
		elseif typeof(where) == "Vector3" then
			return CFrame.new(where :: Vector3)
		elseif type(where) == "string" then
			return marker(where)
		end
		return fail(`a spawn position is a marker name, CFrame or Vector3, got {typeof(where)}`)
	end

	local function spawn(kind: string, where: Where, options: Spawning.Options?): Model
		local settings: Spawning.Options = { snapToGround = true }
		for key, value in pairs(options or {}) do
			settings[key] = value
		end
		settings.parent = params.folder
		settings.tag = handle.tag
		local model, err = Spawning.npc(kind, resolveWhere(where), settings)
		if not model then
			fail(err or `could not spawn {kind}`)
		end
		return model :: Model
	end

	local function spawnRow(kind: string, count: number, where: Where, row: RowOptions?): { Model }
		local spacing = (row and row.spacing) or DEFAULT_ROW_SPACING
		local models: { Model } = {}
		for _, cframe in ipairs(ScopeModule.row(resolveWhere(where), count, spacing)) do
			table.insert(models, spawn(kind, cframe, row and row.options))
		end
		return models
	end

	local function spawned(kind: string?): { Model }
		local models: { Model } = {}
		for _, model in ipairs(Spawning.all(handle.tag)) do
			if kind == nil or string.lower(Spawning.kindOf(model)) == string.lower(kind) then
				table.insert(models, model)
			end
		end
		return models
	end

	local function status(target: any, effectId: string, effectParams: any?): number
		local targets: { Model }
		if type(target) == "string" then
			targets = spawned(target)
		elseif typeof(target) == "Instance" and target:IsA("Model") then
			targets = { target }
		elseif type(target) == "table" then
			targets = target
		else
			return fail(`status target must be a kind name, a Model or a list of Models, got {typeof(target)}`)
		end
		local registrar = require(Server.Services.Registrar) :: any
		local statusEffects = require(Server.StatusEffects.StatusEffectsService) :: any
		local sourceId = params.player and registrar.getPlayerId(params.player)
		local applied = 0
		for _, model in ipairs(targets) do
			local targetId = entityOf(model)
			if targetId and model:GetAttribute("Dead") ~= true then
				statusEffects.apply(targetId, effectId, sourceId, effectParams)
				applied += 1
			end
		end
		return applied
	end

	local function give(itemId: string, count: number?, meta: { [string]: any }?)
		local player = params.player
		local registrar = require(Server.Services.Registrar) :: any
		local playerId = player and registrar.getPlayerId(player)
		if not playerId then
			fail("give needs the scenario's player, and there is none")
		end
		local inventory = require(Server.Inventory.InventoryService) :: any
		if not inventory.addItem(playerId, itemId, count or 1, meta) then
			fail(`could not give {count or 1}x {itemId} (unknown item or no room)`)
		end
	end

	local function run(text: string): any
		local devCommands = require(devFolder.Commands) :: any
		local result = devCommands.run(text, params.player)
		if not result.ok then
			fail(`'{text}' failed: {result.message}`)
		end
		return result
	end

	local function after(seconds: number, fn: () -> ())
		table.insert(handle.threads, task.delay(seconds, guarded, "after", fn))
	end

	local function every(seconds: number, fn: () -> ())
		table.insert(
			handle.threads,
			task.spawn(function()
				while not handle.closed do
					task.wait(seconds)
					guarded("every", fn)
				end
			end)
		)
	end

	local function track(instance: Instance): Instance
		table.insert(handle.tracked, instance)
		return instance
	end

	local function onCleanup(fn: () -> ())
		table.insert(handle.cleanups, fn)
	end

	handle.scope = {
		id = params.id,
		player = params.player,
		players = Players:GetPlayers(),
		stage = stage,
		folder = params.folder,
		marker = marker,
		markers = markers,
		spawn = spawn,
		spawnRow = spawnRow,
		spawned = spawned,
		status = status,
		give = give,
		run = run,
		after = after,
		every = every,
		track = track,
		onCleanup = onCleanup,
	}
	return handle
end

-- Sets server debug flags for the scenario's duration, remembering the value each had before the
-- scenario first changed it.
function ScopeModule.setFlags(handle: Handle, flags: { [string]: boolean })
	local all = DebugConfig.getAll()
	for name, value in pairs(flags) do
		if handle.flagsBefore[name] == nil then
			handle.flagsBefore[name] = all[name] == true
		end
		DebugConfig.set(name, value)
	end
end

-- Removes everything the scope made. Safe to call twice.
function ScopeModule.close(handle: Handle)
	if handle.closed then
		return
	end
	handle.closed = true

	for _, thread in ipairs(handle.threads) do
		pcall(task.cancel, thread)
	end
	for index = #handle.cleanups, 1, -1 do
		local ok, err = xpcall(handle.cleanups[index], debug.traceback)
		if not ok then
			warn(`[Scenarios] {handle.scope.id}: cleanup failed: {err}`)
		end
	end

	Spawning.removeAll({ tag = handle.tag })

	for _, instance in ipairs(handle.tracked) do
		instance:Destroy()
	end
	if handle.ownsFolder then
		handle.scope.folder:Destroy()
	end

	local lootDrops = require(Server.Inventory.Domain.LootDropService) :: any
	for _, drop in ipairs(CollectionService:GetTagged(LOOT_TAG)) do
		local uid = drop:GetAttribute("ItemUid")
		local record = Characters.dropOrigin(drop)
		if type(uid) ~= "string" or handle.lootBefore[uid] or not record then
			continue
		end
		if record.owner == nil or record.sandboxed then
			lootDrops.cleanup(uid)
		elseif returnToOwner(record.owner, uid) then
			lootDrops.cleanup(uid)
		else
			stranded[uid] = record.owner
		end
	end
	-- Real items an earlier teardown had to leave in the world go home as soon as their owner is back
	-- on the real save.
	for uid, owner in pairs(stranded) do
		if not lootDrops.get(uid) or owner.Parent ~= Players then
			stranded[uid] = nil
		elseif returnToOwner(owner, uid) then
			lootDrops.cleanup(uid)
			stranded[uid] = nil
		end
	end

	for name, value in pairs(handle.flagsBefore) do
		DebugConfig.set(name, value)
	end
end

return ScopeModule
