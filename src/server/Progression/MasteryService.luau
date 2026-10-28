--!strict
-- MasteryService: mastery progress, earned by use (docs/planning/progression-direction.md, "Mastery
-- XP from use"; docs/tasks/mastery-model-v2.md).
--
-- XP lives in the player's save per track and branch (`progression.masteries[track].branches`) and
-- is changed there directly; levels and unlocks are derived from it (shared/progression). Branch XP
-- and form selections reach the owning client through ProgressionSync, as its "masteries" and
-- "shapes" sections.
--
-- Where XP comes from:
--   * A use (a cast, or one combo step) gives a little flat XP to its track while the track is below
--     the training cap.
--   * A use that connects with an NPC gives the NPC's mastery value, scaled by the share of its
--     health the hit removed and the skill's tier, up to a ceiling per use. A training target gives
--     flat training XP instead, below the cap only.
--   * Element damage in a hit credits that element's track for its share of the damage.
-- What a use feeds: the basic attack's selected form's node (MasteryTrees), or a skill's `mastery`
-- tag in its shared spec. An infused basic attack also feeds its infusion's node, in the element's
-- track: its use and training XP, and the element's share of what a hit earns. Element damage from
-- anything else lands in the element's trunk.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local StatTypes = require(ReplicatedStorage.Shared.StatTypes)
local MasteryTracks = require(ReplicatedStorage.Shared.progression.MasteryTracks)
local MasteryTrees = require(ReplicatedStorage.Shared.progression.MasteryTrees)
local MasteryTree = require(ReplicatedStorage.Shared.progression.MasteryTree)
local MasteryXP = require(ReplicatedStorage.Shared.progression.MasteryXP)
local BasicAttackForm = require(ReplicatedStorage.Shared.skills.BasicAttackForm)
local ClientSpec = require(ReplicatedStorage.Shared.skills.ClientSpec)

local Server = ServerScriptService.Server
local PlayerDataService = require(Server.PlayerData.PlayerDataService)
local Registrar = require(Server.Services.Registrar)
local CombatService = require(Server.Services.CombatService)
local StatsManager = require(Server.Stats.StatsManager)
local CombatLoadoutService = require(Server.Inventory.CombatLoadout.CombatLoadoutService)
local BaseSkill = require(Server.SkillsFramework.Skills.BaseSkill)
local ProgressionSync = require(script.Parent.ProgressionSync)
local Networking = require(ReplicatedStorage.Shared.Networking)

local dispatcher = Networking.server() :: any

type PlayerSaveData = PlayerDataService.PlayerSaveData

local BASIC_ATTACK_SKILL = "BasicAttack"
local BRANCHES = { "trunk", "a", "b" }

-- What a use feeds: a track, the branches it splits between, and the skill's tier.
type Credit = {
	track: string,
	branches: { [string]: number },
	tier: number,
}

local MasteryService = {}

local progressListeners: { (Player) -> () } = {}

local function branchesOf(data: PlayerSaveData, trackId: string): { [string]: number }
	local masteries = data.progression.masteries
	local entry = masteries[trackId]
	if type(entry) ~= "table" or type(entry.branches) ~= "table" then
		entry = { branches = {} }
		masteries[trackId] = entry
	end
	return entry.branches
end

local function totalOf(data: PlayerSaveData, trackId: string): number
	local entry = data.progression.masteries[trackId]
	return if type(entry) == "table" and type(entry.branches) == "table" then MasteryXP.totalOf(entry.branches) else 0
end

-- Nodes of a track open now. End nodes count attunement, so attuning can open one.
local function unlockedIn(data: PlayerSaveData, trackId: string): { [string]: boolean }
	local out: { [string]: boolean } = {}
	local tree = MasteryTrees.get(trackId)
	if not tree then
		return out
	end
	local branches = branchesOf(data, trackId)
	local attuned = table.find(data.progression.attunement or {}, trackId) ~= nil
	for _, node in ipairs(tree.nodes) do
		if MasteryTree.isUnlocked(node, branches, attuned) then
			out[node.id] = true
		end
	end
	return out
end

-- Nodes that opened since `before` become unseen: the canvas marks them until the player looks.
local function noteUnlocks(data: PlayerSaveData, trackId: string, before: { [string]: boolean })
	local unseen = data.progression.unseen
	for nodeId in pairs(unlockedIn(data, trackId)) do
		if not before[nodeId] and not table.find(unseen, nodeId) then
			table.insert(unseen, nodeId)
		end
	end
end

local function ranksOf(branches: { [string]: number }): string
	return `{MasteryXP.rankOf("trunk", branches)}/{MasteryXP.rankOf("a", branches)}/{MasteryXP.rankOf("b", branches)}`
end

-- Every track's branch XP, keyed by track id: what the shared unlock rule reads.
function MasteryService.masteriesOf(data: PlayerSaveData): { [string]: { [string]: number } }
	local out: { [string]: { [string]: number } } = {}
	for _, track in ipairs(MasteryTracks.list()) do
		local entry = data.progression.masteries[track.id]
		local branches: { [string]: number } = {}
		if type(entry) == "table" and type(entry.branches) == "table" then
			for _, branch in ipairs(BRANCHES) do
				local xp = entry.branches[branch]
				if type(xp) == "number" then
					branches[branch] = xp
				end
			end
		end
		out[track.id] = branches
	end
	return out
end

-- Called when anything derived from a player's mastery may have changed: what they could select
-- has opened or closed, or a level that scales what is in use (an infusion's potency) moved.
function MasteryService.onProgressChanged(listener: (Player) -> ())
	table.insert(progressListeners, listener)
end

function MasteryService.getLevel(player: Player, trackId: string): number
	local data = PlayerDataService.get(player)
	return if data then MasteryXP.levelOf(totalOf(data, trackId)) else 0
end

-- Add `amount` XP to one branch of a track, up to the branch's cap. Returns the XP actually added.
function MasteryService.grant(player: Player, trackId: string, branch: string, amount: number): number
	local data = PlayerDataService.get(player)
	if not data or not MasteryTracks.get(trackId) or not table.find(BRANCHES, branch) or amount <= 0 then
		return 0
	end
	local branches = branchesOf(data, trackId)
	local current = branches[branch] or 0
	local cap = MasteryXP.capOf(branch)
	if current >= cap then
		-- Mastered: nothing is redirected elsewhere, so focus still decides what grows.
		return 0
	end

	local levelBefore = MasteryXP.levelOf(MasteryXP.totalOf(branches))
	local ranksBefore = ranksOf(branches)
	local unlockedBefore = unlockedIn(data, trackId)
	local added = math.min(amount, cap - current)
	branches[branch] = current + added

	local levelAfter = MasteryXP.levelOf(MasteryXP.totalOf(branches))
	if ranksOf(branches) ~= ranksBefore or levelAfter ~= levelBefore then
		noteUnlocks(data, trackId, unlockedBefore)
		for _, listener in ipairs(progressListeners) do
			task.spawn(listener, player)
		end
	end
	ProgressionSync.schedule(
		player,
		if levelAfter ~= levelBefore then { kind = "masteryLevel", track = trackId, level = levelAfter } else nil
	)
	return added
end

-- Set a branch's XP outright. For tooling; play earns XP through `grant`.
function MasteryService.setBranchXp(player: Player, trackId: string, branch: string, xp: number)
	local data = PlayerDataService.get(player)
	if not data or not MasteryTracks.get(trackId) or not table.find(BRANCHES, branch) then
		return
	end
	local branches = branchesOf(data, trackId)
	local unlockedBefore = unlockedIn(data, trackId)
	branches[branch] = math.clamp(xp, 0, MasteryXP.capOf(branch))
	noteUnlocks(data, trackId, unlockedBefore)
	for _, listener in ipairs(progressListeners) do
		task.spawn(listener, player)
	end
	ProgressionSync.schedule(player, nil)
end

-- What a use of `skillName` by `casterId` feeds, or nil for skills that teach nothing.
local function creditFor(casterId: string, skillName: string?): Credit?
	if skillName == BASIC_ATTACK_SKILL then
		local profile = BasicAttackForm.resolve(CombatLoadoutService.get(casterId)).profile
		local node, tree = MasteryTrees.nodeForShape(profile.id)
		if not node or not tree then
			return nil
		end
		return { track = tree.track, branches = MasteryTree.creditFor(node), tier = 1 }
	end
	local spec = if skillName then (ClientSpec :: any)[skillName] else nil
	local mastery = spec and spec.mastery
	if not mastery then
		return nil
	end
	return { track = mastery.track, branches = { [mastery.branch] = 1 }, tier = mastery.tier or 1 }
end

-- What the infusion of an infused basic attack feeds, in its element's track.
local function infusionCreditFor(casterId: string, skillName: string?): Credit?
	if skillName ~= BASIC_ATTACK_SKILL then
		return nil
	end
	local infusion = BasicAttackForm.resolve(CombatLoadoutService.get(casterId)).infusion
	if not infusion then
		return nil
	end
	local node, tree = MasteryTrees.node(infusion.id)
	if not node or not tree then
		return nil
	end
	return { track = tree.track, branches = MasteryTree.creditFor(node), tier = 1 }
end

-- Everything a use of `skillName` feeds: its own track, and its infusion's element.
local function creditsFor(casterId: string, skillName: string?): { Credit }
	local out: { Credit } = {}
	local own = creditFor(casterId, skillName)
	if own then
		table.insert(out, own)
	end
	local infusion = infusionCreditFor(casterId, skillName)
	if infusion then
		table.insert(out, infusion)
	end
	return out
end

local function grantSplit(player: Player, credit: Credit, amount: number)
	for branch, weight in pairs(credit.branches) do
		MasteryService.grant(player, credit.track, branch, amount * weight)
	end
end

local function belowTrainingCap(data: PlayerSaveData, trackId: string): boolean
	return MasteryXP.levelOf(totalOf(data, trackId)) < MasteryXP.TRAINING_CAP_LEVEL
end

local function onUsed(casterId: string, skillName: string)
	local player = Registrar.getPlayerById(casterId)
	local data = player and PlayerDataService.get(player)
	if not player or not data then
		return
	end
	for _, credit in ipairs(creditsFor(casterId, skillName)) do
		if belowTrainingCap(data, credit.track) then
			grantSplit(player, credit, MasteryXP.USE_XP)
		end
	end
end

local function onHit(sourceEntityId: string, targetEntityId: string, result: any, metadata: any)
	if sourceEntityId == targetEntityId or Registrar.isPlayerEntity(targetEntityId) then
		return
	end
	local player = Registrar.getPlayerById(sourceEntityId)
	local data = player and PlayerDataService.get(player)
	local target = Registrar.getEntityById(targetEntityId)
	if not player or not data or not target then
		return
	end
	local credit = creditFor(sourceEntityId, metadata.skillId)
	local infusionCredit = infusionCreditFor(sourceEntityId, metadata.skillId)

	if target:GetAttribute("TrainingTarget") == true then
		for _, each in ipairs(creditsFor(sourceEntityId, metadata.skillId)) do
			if belowTrainingCap(data, each.track) then
				grantSplit(player, each, MasteryXP.TRAINING_HIT_XP)
			end
		end
		return
	end

	local value = target:GetAttribute("MasteryValue")
	local maxHealth = StatsManager.getPoolMaxValue(targetEntityId, StatTypes.PoolStats.Health)
	local removed = result.healthRemoved
	if type(value) ~= "number" or value <= 0 or not maxHealth or maxHealth <= 0 or type(removed) ~= "number" then
		return
	end
	local earned = MasteryXP.connectXp(value, removed / maxHealth, if credit then credit.tier else 1)
	if earned <= 0 then
		return
	end

	if credit then
		grantSplit(player, credit, math.min(earned, MasteryXP.ceilingFor(totalOf(data, credit.track))))
	end

	-- Each element in the hit is credited for its share of the damage: through the infusion's node
	-- when the infusion put it there, to the element's trunk otherwise.
	local total = result.totalDamage
	if type(total) == "number" and total > 0 and type(result.byType) == "table" then
		for damageType, amount in pairs(result.byType) do
			local element = MasteryTracks.forDamageType(damageType)
			if element and type(amount) == "number" and amount > 0 then
				local share = math.min(earned * amount / total, MasteryXP.ceilingFor(totalOf(data, element.id)))
				local into: Credit = if infusionCredit and infusionCredit.track == element.id
					then infusionCredit
					else { track = element.id, branches = { trunk = 1 }, tier = 1 }
				grantSplit(player, into, share)
			end
		end
	end
end

-- The player has looked at these nodes: they stop being marked new.
function MasteryService.markSeen(player: Player, nodeIds: any)
	local data = PlayerDataService.get(player)
	if not data or type(nodeIds) ~= "table" then
		return
	end
	local unseen = data.progression.unseen
	local changed = false
	for _, nodeId in ipairs(nodeIds) do
		local index = if type(nodeId) == "string" then table.find(unseen, nodeId) else nil
		if index then
			table.remove(unseen, index)
			changed = true
		end
	end
	if changed then
		ProgressionSync.schedule(player, nil)
	end
end

function MasteryService.start()
	CombatService.onHit(onHit)
	BaseSkill.onUsed(onUsed)

	ProgressionSync.addSection("masteries", function(data)
		local masteries: { [string]: any } = {}
		for trackId, branches in pairs(MasteryService.masteriesOf(data)) do
			masteries[trackId] = { branches = branches }
		end
		return masteries
	end)
	ProgressionSync.addSection("shapes", function(data)
		return table.clone(data.progression.shapes)
	end)
	ProgressionSync.addSection("unseen", function(data)
		return table.clone(data.progression.unseen)
	end)

	-- Only removes entries, so a spammed request can do no more than one honest one.
	dispatcher:onRequest("ProgressionSeen", function(payload, _meta, context): { ok: boolean }
		local player = context.player
		if player and type(payload) == "table" then
			MasteryService.markSeen(player, payload.nodeIds)
		end
		return { ok = true }
	end)
end

return MasteryService
