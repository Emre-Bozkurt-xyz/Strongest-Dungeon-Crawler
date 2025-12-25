--!strict
-- SkillMetadataService: Server-side skill metadata calculation and emission
-- Computes costs, damage estimates, and other skill metadata using full observer/mediator pipeline
-- Sends calculated metadata to clients via SkillMetadataUpdate events on the Skills channel
-- Responds to SkillMetadataSnapshot requests for initial client sync

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Registrar = require(ServerScriptService.Server.Services.Registrar)
local Networking = require(ReplicatedStorage.Shared.Networking)
local StatsManager = require(ServerScriptService.Server.Stats.StatsManager)
local SkillMediator = require(ServerScriptService.Server.Stats.SkillMediator)
local SkillsConfig = require(script.Parent.SkillsConfig)
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)
local SkillQueryTypes = require(ReplicatedStorage.Shared.skills.SkillQueryTypes)

type SkillData = SkillsConfig.SkillData
type PoolType = StatTypes.PoolType

local EVENT_NAME = "SkillMetadataUpdate"
local REQUEST_SNAPSHOT = "SkillMetadataSnapshot"
local SKILLS_CHANNEL_NAME = "Skills"

local dispatcher = Networking.server()
local dispatcherAny = dispatcher :: any
dispatcherAny:_ensureChannel(SKILLS_CHANNEL_NAME)

local SkillMetadataService = {}

-- Track last sent metadata to avoid redundant updates
local lastSentMetadata: { [string]: { [string]: any } } = {} -- entityId -> skillName -> metadata

local function buildCostContext(
	entityId: string,
	skillName: string,
	skillData: SkillData,
	baseResource: PoolType,
	baseAmount: number,
	step: number?
): SkillQueryTypes.SkillQueryContext
	local meta = {
		resource = baseResource,
		skill = skillName,
		skillId = (skillData :: any).id or skillData.name or skillName,
		skillCategory = skillData.category,
		skillTags = (skillData.tags or skillData.categories),
		casterId = entityId,
		step = step,
	}

	return {
		entityId = entityId,
		skillId = skillName,
		event = "resolveSkillCost",
		tags = skillData.tags,
		step = step,
		metadata = meta,
		base = {
			resource = baseResource,
			amount = baseAmount,
		},
	}
end

local function resolveCostPreview(
	entityId: string,
	skillName: string,
	skillData: SkillData,
	baseResource: PoolType,
	baseAmount: number,
	step: number?
)
	local ctx = buildCostContext(entityId, skillName, skillData, baseResource, baseAmount, step)
	local result = SkillMediator.resolve(ctx)
	local values = result.values
	local resolvedResource = (values and values.resource) or baseResource
	local resolvedAmount = (values and values.amount) or baseAmount

	local preview = StatsManager.resolvePoolCost(entityId, resolvedResource, resolvedAmount, {
		metadata = ctx.metadata,
	})

	if preview then
		preview.poolName = resolvedResource
		preview.finalCost = resolvedAmount
		return preview
	end

	return {
		poolName = resolvedResource,
		finalCost = resolvedAmount,
		currentValue = 0,
		maxValue = 0,
	}
end

-- Calculate resource cost for a skill using full observer/mediator pipeline
local function calculateCost(entityId: string, skillName: string, skillData: SkillData): (number?, string?, { number }?)
	local cost = skillData.cost
	local baseResource: PoolType = (skillData.baseResource :: any) or StatTypes.PoolStats.Stamina
	local costResource: PoolType = baseResource
	local comboCosts: { number }? = nil

	-- Handle combo skills with per-step costs
	if skillData.combo and skillData.costs then
		local tempComboCosts = {}
		for step = 1, skillData.combo.steps do
			local stepCost = skillData.costs[step] or skillData.costs[#skillData.costs] or 0
			local preview = resolveCostPreview(entityId, skillName, skillData, baseResource, stepCost, step)
			local finalCost = preview and preview.finalCost or stepCost
			tempComboCosts[step] = finalCost
			if step == 1 then
				cost = finalCost
				costResource = (preview and preview.poolName) or baseResource
			end
		end

		comboCosts = tempComboCosts
	elseif cost and cost > 0 then
		-- Single-cost skill - preview with mediators/modifiers
		local preview = resolveCostPreview(entityId, skillName, skillData, baseResource, cost, nil)
		if preview then
			costResource = preview.poolName
			cost = preview.finalCost
		end
	end

	return cost, costResource, comboCosts
end

-- Calculate full metadata for a skill
local function calculateMetadata(entityId: string, skillName: string): { [string]: any }?
	local skillData = SkillsConfig.skills[skillName]
	if not skillData then
		return nil
	end

	local cost, costResource, comboCosts = calculateCost(entityId, skillName, skillData)

	-- Build extensible metadata object
	local metadata: { [string]: any } = {}

	if cost and cost > 0 then
		metadata.cost = cost
		metadata.costResource = costResource
	end

	if comboCosts then
		metadata.comboCosts = comboCosts
	end

	-- Add combo timing information so client can calculate windows
	if skillData.combo then
		metadata.combo = {
			steps = skillData.combo.steps,
			window = skillData.combo.window,
			stepDelays = skillData.combo.stepDelays,
			hitDelays = skillData.combo.hitDelays,
			recovery = skillData.combo.recovery,
			stepDurations = skillData.combo.stepDurations,
			comboCooldown = skillData.combo.comboCooldown,
		}
	end

	-- TODO: Add damage estimates when damage calculation system is ready
	-- metadata.estimatedDamage = calculateDamage(entityId, skillName, skillData)
	-- metadata.damageBreakdown = calculateDamageBreakdown(entityId, skillName, skillData)

	return metadata
end

-- Send metadata update for a single skill to a specific player
function SkillMetadataService.updateSkill(player: Player, skillName: string)
	if not player.Character then
		return
	end
	local entityId = Registrar.getEntityId(player.Character)
	if not entityId then
		return
	end

	local metadata = calculateMetadata(entityId, skillName)
	if not metadata then
		return
	end

	-- Check if metadata changed (avoid redundant updates)
	local lastSent = lastSentMetadata[entityId]
	if lastSent and lastSent[skillName] then
		local changed = false
		for key, value in pairs(metadata) do
			if lastSent[skillName][key] ~= value then
				changed = true
				break
			end
		end
		if not changed then
			return -- No change, skip update
		end
	end

	-- Store sent metadata
	if not lastSentMetadata[entityId] then
		lastSentMetadata[entityId] = {}
	end
	lastSentMetadata[entityId][skillName] = table.clone(metadata)

	-- Send to client using dispatcher:emit with targets option
	dispatcherAny:emit(EVENT_NAME, {
		skillName = skillName,
		metadata = metadata,
	}, { targets = { player } })
end

-- Send metadata updates for all skills to a specific player
function SkillMetadataService.updateAllSkills(player: Player)
	if not player.Character then
		return
	end
	local entityId = Registrar.getEntityId(player.Character)
	if not entityId then
		return
	end

	for skillName, _ in pairs(SkillsConfig.skills) do
		SkillMetadataService.updateSkill(player, skillName)
	end
end

-- Handle snapshot request from client (initial sync)
dispatcherAny:onRequest(REQUEST_SNAPSHOT, function(_data: any, _meta: any, context: any)
	local player = context and context.player

	if not player or not player.Character then
		return {}
	end

	local entityId = Registrar.getEntityId(player.Character)
	if not entityId then
		return {}
	end

	local snapshot: { [string]: any } = {}

	for skillName, _ in pairs(SkillsConfig.skills) do
		local metadata = calculateMetadata(entityId, skillName)
		if metadata then
			snapshot[skillName] = metadata
		end
	end

	return snapshot
end)

-- Listen to stat changes and update metadata for all players
-- TODO: Hook into StatsManager or StatusEffectsService change events
-- For now, external systems should call updateSkill() or updateAllSkills() when relevant

-- Clean up on player removal
Players.PlayerRemoving:Connect(function(player)
	if not player.Character then
		return
	end
	local entityId = Registrar.getEntityId(player.Character)
	if entityId then
		lastSentMetadata[entityId] = nil
	end
end)

return SkillMetadataService
