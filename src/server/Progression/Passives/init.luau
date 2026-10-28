--!strict
-- PassiveService: puts passive nodes into effect (docs/tasks/passives.md).
--
-- Which nodes are in effect is derived, like every unlock: from saved branch XP, attunement and the
-- chosen selectable passives, each time any of them changes. A node in effect contributes its
-- effects (NodeEffects) at a scale that grows with its branch and with an attuned element.
--
-- The effects themselves are implemented by kinds (./Kinds), one module per `kind`. This service only
-- decides what is in force for whom and calls each kind at its moments:
--   apply     -- ahead of time, on every recompute (stats, cost modifiers, numbers skills read)
--   outgoing  -- an attack the entity makes, about to land (CombatService attack hook)
--   incoming  -- an attack on the entity, about to land
--   afterHit  -- an attack the entity made, once it landed (CombatService.onHit)
--   onKill    -- an NPC the entity killed (NPCDeath)
--   onUse     -- a skill use the entity paid for (BaseSkill.onUsed)
--
-- Selectable passives: up to PassivePool.slotsFor(level) chosen at once, from every tree, saved as
-- `progression.passives`. The save is cut to the slots the level allows when read.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Networking = require(ReplicatedStorage.Shared.Networking)
local MasteryTracks = require(ReplicatedStorage.Shared.progression.MasteryTracks)
local MasteryTrees = require(ReplicatedStorage.Shared.progression.MasteryTrees)
local MasteryTree = require(ReplicatedStorage.Shared.progression.MasteryTree)
local NodeEffects = require(ReplicatedStorage.Shared.progression.NodeEffects)
local PassivePool = require(ReplicatedStorage.Shared.progression.PassivePool)

local Server = ServerScriptService.Server
local PlayerDataService = require(Server.PlayerData.PlayerDataService)
local Registrar = require(Server.Services.Registrar)
local CombatService = require(Server.Services.CombatService)
local CombatLoadoutService = require(Server.Inventory.CombatLoadout.CombatLoadoutService)
local BaseSkill = require(Server.SkillsFramework.Skills.BaseSkill)
local NPCDeath = require(Server.NPCService.NPCDeath)
local MasteryService = require(script.Parent.MasteryService)
local AttunementService = require(script.Parent.AttunementService)
local CharacterService = require(script.Parent.CharacterService)
local ProgressionSync = require(script.Parent.ProgressionSync)
local Facts = require(script.Facts)
local KindTypes = require(script.KindTypes)

type PlayerSaveData = PlayerDataService.PlayerSaveData
type Active = KindTypes.Active
type Kind = KindTypes.Kind

local dispatcher = Networking.server() :: any

-- A kill is credited to whoever hit last, within this many seconds.
local KILL_CREDIT_WINDOW = 10
local RATE_WINDOW = 5
local RATE_MAX = 20

local PassiveService = {}

local kinds: { [string]: Kind } = {}
for _, module in ipairs(script.Kinds:GetChildren()) do
	if module:IsA("ModuleScript") then
		local loaded = require(module) :: any
		local list: { Kind } = if loaded.kind then { loaded } else loaded
		for _, kind in ipairs(list) do
			assert(kinds[kind.kind] == nil, `PassiveService: kind '{kind.kind}' implemented twice`)
			kinds[kind.kind] = kind
		end
	end
end

-- Every effect in the content must have a kind that implements it; a typo would do nothing.
for _, track in ipairs(MasteryTracks.list()) do
	local tree = MasteryTrees.get(track.id)
	for _, node in ipairs(if tree then tree.nodes else {}) do
		for _, effect in ipairs(NodeEffects.of(node.id) or {}) do
			assert(kinds[effect.kind], `PassiveService: node '{node.id}' uses unknown effect kind '{effect.kind}'`)
		end
	end
end

-- Effects in force, by entity and kind.
local byEntity: { [string]: { [string]: { Active } } } = {}
local entityOfPlayer: { [Player]: string } = {}
local lastHitBy: { [string]: { sourceId: string, at: number } } = {}
local pendingRefresh: { [Player]: boolean } = {}
local rates: { [Player]: { windowStart: number, count: number } } = {}

-- The selectable passives a character has chosen that their level has slots for.
function PassiveService.chosenOf(player: Player, data: PlayerSaveData): { string }
	local saved = data.progression.passives
	local slots = PassivePool.slotsFor(CharacterService.getLevel(player))
	local out: { string } = {}
	if type(saved) ~= "table" then
		return out
	end
	for _, nodeId in ipairs(saved) do
		if #out >= slots then
			break
		end
		if type(nodeId) == "string" then
			table.insert(out, nodeId)
		end
	end
	return out
end

local function activesFor(player: Player, data: PlayerSaveData): { [string]: { Active } }
	local masteries = MasteryService.masteriesOf(data)
	local attunement = AttunementService.attunedOf(data)
	local chosen = PassiveService.chosenOf(player, data)
	local grouped: { [string]: { Active } } = {}
	for _, track in ipairs(MasteryTracks.list()) do
		local tree = MasteryTrees.get(track.id)
		local branches = masteries[track.id] or {}
		local attuned = table.find(attunement, track.id) ~= nil
		for _, node in ipairs(if tree then tree.nodes else {}) do
			local effects = NodeEffects.of(node.id)
			if
				not effects
				or not MasteryTree.isUnlocked(node, branches, attuned)
				or not MasteryTree.isActive(node, track.id, attuned)
				or (node.kind == "select" and not table.find(chosen, node.id))
			then
				continue
			end
			local scale = NodeEffects.scaleOf(node, track.id, branches, attuned)
			for index, effect in ipairs(effects) do
				local list = grouped[effect.kind] or {}
				table.insert(list, {
					nodeId = node.id,
					effect = effect,
					scale = scale,
					sourceId = `passive::{node.id}::{index}`,
				})
				grouped[effect.kind] = list
			end
		end
	end
	return grouped
end

-- Put the player's passives into effect as their progress, selections and weapon stand now.
function PassiveService.refresh(player: Player)
	local data = PlayerDataService.get(player)
	local entityId = Registrar.getPlayerId(player)
	if not data or not entityId then
		return
	end
	entityOfPlayer[player] = entityId
	local grouped = activesFor(player, data)
	local loadout = Facts.loadoutOf(entityId)
	local attuned: { [string]: boolean } = {}
	for _, trackId in ipairs(AttunementService.attunedOf(data)) do
		attuned[trackId] = true
	end
	loadout.attuned = attuned
	for name, kind in pairs(kinds) do
		if kind.apply then
			local ok, err = pcall(kind.apply :: any, entityId, grouped[name] or {}, loadout)
			if not ok then
				warn(`[PassiveService] kind '{name}' failed to apply:`, err)
			end
		end
	end
	byEntity[entityId] = grouped
end

-- Refresh at the end of the frame, once for everything that changed in it.
local function scheduleRefresh(player: Player)
	if pendingRefresh[player] then
		return
	end
	pendingRefresh[player] = true
	task.defer(function()
		pendingRefresh[player] = nil
		if player.Parent then
			PassiveService.refresh(player)
		end
	end)
end

local function release(player: Player)
	local entityId = entityOfPlayer[player]
	entityOfPlayer[player] = nil
	rates[player] = nil
	if not entityId then
		return
	end
	for _, kind in pairs(kinds) do
		if kind.clear then
			pcall(kind.clear, entityId)
		end
	end
	byEntity[entityId] = nil
end

-- Choose or drop the selectable passive `nodeId`.
function PassiveService.select(player: Player, nodeId: any, selected: any): (boolean, string?)
	local data = PlayerDataService.get(player)
	if not data then
		return false, "not_loaded"
	end
	local node, tree = nil, nil
	if type(nodeId) == "string" then
		node, tree = MasteryTrees.node(nodeId)
	end
	if not node or not tree or node.kind ~= "select" then
		return false, "unknown_passive"
	end
	local saved = data.progression.passives
	if type(saved) ~= "table" then
		saved = {}
		data.progression.passives = saved
	end
	local chosen = PassiveService.chosenOf(player, data)
	if selected ~= true then
		local index = table.find(saved, node.id)
		if index then
			table.remove(saved, index)
		end
	elseif not table.find(chosen, node.id) then
		local attuned = table.find(AttunementService.attunedOf(data), tree.track) ~= nil
		local branches = MasteryService.masteriesOf(data)[tree.track] or {}
		if not MasteryTree.isUnlocked(node, branches, attuned) or not MasteryTree.isActive(node, tree.track, attuned) then
			return false, "locked"
		end
		if #chosen >= PassivePool.slotsFor(CharacterService.getLevel(player)) then
			return false, "no_free_slot"
		end
		-- Chosen beyond the slots (from a higher level, before a retune) are dropped from the save
		-- rather than kept ahead of this one.
		table.clear(saved)
		for _, id in ipairs(chosen) do
			table.insert(saved, id)
		end
		table.insert(saved, node.id)
	end
	PassiveService.refresh(player)
	ProgressionSync.publish(player, nil)
	return true, nil
end

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

local function onAttack(ctx: CombatService.AttackHookContext)
	local source = byEntity[ctx.sourceId]
	local target = byEntity[ctx.targetId]
	if not source and not target then
		return
	end
	local facts = Facts.hit(ctx.sourceId, ctx.targetId, ctx.metadata, nil)
	if source then
		for name, actives in pairs(source) do
			local kind = kinds[name]
			if kind and kind.outgoing and #actives > 0 then
				kind.outgoing(ctx, facts, actives)
			end
		end
	end
	if target then
		for name, actives in pairs(target) do
			local kind = kinds[name]
			if kind and kind.incoming and #actives > 0 then
				kind.incoming(ctx, facts, actives)
			end
		end
	end
end

local function onHit(sourceId: string, targetId: string, result: any, metadata: any)
	if sourceId == targetId then
		return
	end
	if not Registrar.isPlayerEntity(targetId) then
		lastHitBy[targetId] = { sourceId = sourceId, at = os.clock() }
	end
	local source = byEntity[sourceId]
	-- A status's own damage (a burn's tick) is not a hit to react to: a fire tick that could ignite
	-- would keep a burn feeding itself. It still counts for the kill above.
	if not source or (type(metadata) == "table" and metadata.effectId ~= nil) then
		return
	end
	local facts = Facts.hit(sourceId, targetId, metadata, result)
	for name, actives in pairs(source) do
		local kind = kinds[name]
		if kind and kind.afterHit and #actives > 0 then
			local ok, err = pcall(kind.afterHit :: any, facts, actives)
			if not ok then
				warn(`[PassiveService] kind '{name}' failed after a hit:`, err)
			end
		end
	end
end

local function onDeath(entityId: string, model: Model)
	local last = lastHitBy[entityId]
	lastHitBy[entityId] = nil
	if not last or os.clock() - last.at > KILL_CREDIT_WINDOW then
		return
	end
	local killer = byEntity[last.sourceId]
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not killer or not root then
		return
	end
	local kill: KindTypes.KillFacts = {
		killerId = last.sourceId,
		targetId = entityId,
		model = model,
		position = root.Position,
	}
	for name, actives in pairs(killer) do
		local kind = kinds[name]
		if kind and kind.onKill and #actives > 0 then
			local ok, err = pcall(kind.onKill :: any, kill, actives)
			if not ok then
				warn(`[PassiveService] kind '{name}' failed on a kill:`, err)
			end
		end
	end
end

local function onUsed(casterId: string, skillName: string)
	local caster = byEntity[casterId]
	if not caster then
		return
	end
	local loadout = Facts.loadoutOf(casterId)
	for name, actives in pairs(caster) do
		local kind = kinds[name]
		if kind and kind.onUse and #actives > 0 then
			local ok, err = pcall(kind.onUse :: any, casterId, skillName, actives, loadout)
			if not ok then
				warn(`[PassiveService] kind '{name}' failed on a use:`, err)
			end
		end
	end
end

function PassiveService.start()
	CombatService.addAttackHook(onAttack)
	CombatService.onHit(onHit)
	NPCDeath.onDeath(onDeath)
	BaseSkill.onUsed(onUsed)

	MasteryService.onProgressChanged(scheduleRefresh)
	AttunementService.onChanged(scheduleRefresh)
	CharacterService.onLevelChanged(function(player)
		scheduleRefresh(player)
		-- A new slot changes what the canvas offers.
		ProgressionSync.schedule(player, nil)
	end)
	-- What is held decides weapon-limited passives; the combat loadout is also the first thing ready
	-- after a player's stats exist, so it is where a joining player's passives first apply.
	CombatLoadoutService.onChanged(function(entityId)
		local player = Registrar.getPlayerById(entityId)
		if player then
			scheduleRefresh(player)
		end
	end)
	PlayerDataService.onLoaded(function(player)
		scheduleRefresh(player)
	end)
	Players.PlayerRemoving:Connect(release)

	ProgressionSync.addSection("passives", function(data)
		local saved = data.progression.passives
		return if type(saved) == "table" then table.clone(saved) else {}
	end)

	dispatcher:onRequest("ProgressionSelectPassive", function(payload, _meta, context): { ok: boolean, error: string? }
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
		local ok, err = PassiveService.select(player, payload.nodeId, payload.selected)
		return { ok = ok, error = err }
	end)
end

return PassiveService
