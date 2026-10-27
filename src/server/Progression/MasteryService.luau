--!strict
-- MasteryService: mastery progress, earned by use (docs/planning/progression-direction.md, "Mastery
-- XP from use"; docs/tasks/mastery-model-v2.md).
--
-- XP lives in the player's save per track and branch (`progression.masteries[track].branches`) and
-- is changed there directly; levels and unlocks are derived from it (shared/progression). The owning
-- client is sent its progression -- branch XP and its form selections, which the mastery canvas
-- draws together -- whenever any of it changes, at most once per frame.
--
-- Where XP comes from:
--   * A use (a cast, or one combo step) gives a little flat XP to its track while the track is below
--     the training cap.
--   * A use that connects with an NPC gives the NPC's mastery value, scaled by the share of its
--     health the hit removed and the skill's tier, up to a ceiling per use. A training target gives
--     flat training XP instead, below the cap only.
--   * Element damage in a hit credits that element's track for its share of the damage.
-- What a use feeds: the basic attack's selected form's node (MasteryTrees), or a skill's `mastery`
-- tag in its shared spec.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Networking = require(ReplicatedStorage.Shared.Networking)
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)
local MasteryTracks = require(ReplicatedStorage.Shared.progression.MasteryTracks)
local MasteryTrees = require(ReplicatedStorage.Shared.progression.MasteryTrees)
local MasteryTree = require(ReplicatedStorage.Shared.progression.MasteryTree)
local MasteryXP = require(ReplicatedStorage.Shared.progression.MasteryXP)
local BasicAttackProfileRegistry = require(ReplicatedStorage.Shared.skills.BasicAttackProfileRegistry)
local ClientSpec = require(ReplicatedStorage.Shared.skills.ClientSpec)

local Server = ServerScriptService.Server
local PlayerDataService = require(Server.PlayerData.PlayerDataService)
local Registrar = require(Server.Services.Registrar)
local CombatService = require(Server.Services.CombatService)
local StatsManager = require(Server.Stats.StatsManager)
local CombatLoadoutService = require(Server.Inventory.CombatLoadout.CombatLoadoutService)
local BaseSkill = require(Server.SkillsFramework.Skills.BaseSkill)

type PlayerSaveData = PlayerDataService.PlayerSaveData

local dispatcher = Networking.server() :: any

local BASIC_ATTACK_SKILL = "BasicAttack"
local BRANCHES = { "trunk", "a", "b" }

export type LevelUp = {
	track: string,
	level: number,
}

-- What a use feeds: a track, the branches it splits between, and the skill's tier.
type Credit = {
	track: string,
	branches: { [string]: number },
	tier: number,
}

local MasteryService = {}

local unlockListeners: { (Player) -> () } = {}

-- Per player: the level-ups to announce in the next publish, gathered over one frame.
local pendingPublish: { [Player]: { LevelUp } } = {}

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

-- What the owning client is told: every track's branch XP, and its form selections.
function MasteryService.snapshot(player: Player): { [string]: any }?
	local data = PlayerDataService.get(player)
	if not data then
		return nil
	end
	local masteries: { [string]: any } = {}
	for trackId, branches in pairs(MasteryService.masteriesOf(data)) do
		masteries[trackId] = { branches = branches }
	end
	return {
		masteries = masteries,
		shapes = table.clone(data.progression.shapes),
	}
end

-- Send the player their progression now. `levelUps` are announced by the client.
function MasteryService.publish(player: Player, levelUps: { LevelUp }?)
	local payload = MasteryService.snapshot(player)
	if not payload then
		return
	end
	payload.levelUps = levelUps
	dispatcher:emit("ProgressionUpdate", payload, { targets = { player } })
end

-- Publish at the end of the frame, so a hit that feeds several tracks sends one update.
local function schedulePublish(player: Player, levelUp: LevelUp?)
	local pending = pendingPublish[player]
	if not pending then
		pending = {}
		pendingPublish[player] = pending
		task.defer(function()
			local levelUps = pendingPublish[player]
			pendingPublish[player] = nil
			if levelUps and player.Parent then
				MasteryService.publish(player, if #levelUps > 0 then levelUps else nil)
			end
		end)
	end
	if levelUp then
		table.insert(pending, levelUp)
	end
end

-- Called when anything a player could select may have opened or closed.
function MasteryService.onUnlocksChanged(listener: (Player) -> ())
	table.insert(unlockListeners, listener)
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
	local added = math.min(amount, cap - current)
	branches[branch] = current + added

	local levelAfter = MasteryXP.levelOf(MasteryXP.totalOf(branches))
	if ranksOf(branches) ~= ranksBefore then
		for _, listener in ipairs(unlockListeners) do
			task.spawn(listener, player)
		end
	end
	schedulePublish(player, if levelAfter ~= levelBefore then { track = trackId, level = levelAfter } else nil)
	return added
end

-- Set a branch's XP outright. For tooling; play earns XP through `grant`.
function MasteryService.setBranchXp(player: Player, trackId: string, branch: string, xp: number)
	local data = PlayerDataService.get(player)
	if not data or not MasteryTracks.get(trackId) or not table.find(BRANCHES, branch) then
		return
	end
	local branches = branchesOf(data, trackId)
	branches[branch] = math.clamp(xp, 0, MasteryXP.capOf(branch))
	for _, listener in ipairs(unlockListeners) do
		task.spawn(listener, player)
	end
	schedulePublish(player, nil)
end

-- What a use of `skillName` by `casterId` feeds, or nil for skills that teach nothing.
local function creditFor(casterId: string, skillName: string?): Credit?
	if skillName == BASIC_ATTACK_SKILL then
		local profile = BasicAttackProfileRegistry.resolve(CombatLoadoutService.get(casterId))
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
	local credit = creditFor(casterId, skillName)
	if credit and belowTrainingCap(data, credit.track) then
		grantSplit(player, credit, MasteryXP.USE_XP)
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

	if target:GetAttribute("TrainingTarget") == true then
		if credit and belowTrainingCap(data, credit.track) then
			grantSplit(player, credit, MasteryXP.TRAINING_HIT_XP)
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

	-- Each element in the hit is credited for its share of the damage, to its trunk until
	-- infusions exist to say which branch.
	local total = result.totalDamage
	if type(total) == "number" and total > 0 and type(result.byType) == "table" then
		for damageType, amount in pairs(result.byType) do
			local element = MasteryTracks.forDamageType(damageType)
			if element and type(amount) == "number" and amount > 0 then
				local share = earned * amount / total
				MasteryService.grant(player, element.id, "trunk", math.min(share, MasteryXP.ceilingFor(totalOf(data, element.id))))
			end
		end
	end
end

function MasteryService.start()
	CombatService.onHit(onHit)
	BaseSkill.onUsed(onUsed)

	dispatcher:onRequest("ProgressionSnapshot", function(_payload, _meta, context)
		local player = context.player
		return if player then MasteryService.snapshot(player) else nil
	end)

	-- After the request above, which creates the channel this emits on.
	PlayerDataService.onLoaded(function(player)
		MasteryService.publish(player, nil)
	end)
end

return MasteryService
