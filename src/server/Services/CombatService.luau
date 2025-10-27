--!strict
-- Simple combat utility to apply damage to Stats (players) or Humanoids (NPC fallback)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = game:GetService("ServerScriptService").Server

local StatTypes = require(ReplicatedStorage.Shared.StatTypes)
local StatsManager = require(Server.Stats.StatsManager)
local StatusEffectsService = require(script.Parent.Parent.StatusEffects.StatusEffectsService)

local CombatService = {}

export type DamageEffect = { id: string, chance: number?, params: any? }
export type DamageSource = Instance

export type DamageOptions = {
	kind: string?, -- "physical" | "magic" | "true" | custom
	element: string?, -- e.g., fire, ice
	critAllowed: boolean?,
	bypassShield: boolean?,
	bypassArmor: boolean?,
	effects: { DamageEffect }?,
}

type ResourceMetaSnapshot = {
	shield: { [any]: any }?,
	health: { [any]: any }?,
}

export type DamageResult = {
	dodged: boolean,
	crit: boolean,
	baseAmount: number,
	mitigated: number,
	absorbed: number,
	appliedToHealth: number,
	finalAmount: number,
	targetPlayer: Player?,
	targetHumanoid: Humanoid?,
	sourcePlayer: Player?,
	sourceModel: Model?,
	sourceEntity: Instance?,
	-- IDs of any status effects that were applied by this damage instance
	effectsApplied: { string }?,
	resourceMeta: ResourceMetaSnapshot?,
}

local function modelOf(inst: Instance): Model?
	local cur: Instance? = inst
	while cur do
		if cur:IsA("Model") then
			return cur
		end
		cur = cur.Parent
	end
	return nil
end

local function getHumanoidFromModel(model: Model): Humanoid?
	return model:FindFirstChildOfClass("Humanoid") :: Humanoid?
end

function CombatService.getHumanoid(target: Instance): Humanoid?
	if target:IsA("Model") then
		return getHumanoidFromModel(target)
	end
	local m = modelOf(target)
	if m then
		return getHumanoidFromModel(m)
	end
	return nil
end

local function playerFromTarget(target: Instance): Player?
	local m: Model? = nil
	if target:IsA("Model") then
		m = target
	else
		m = modelOf(target)
	end
	if m then
		return Players:GetPlayerFromCharacter(m)
	end
	return nil
end

local function resolveSourceInfo(source: Instance?): (Player?, Model?, Instance?)
	if not source then
		return nil, nil, nil
	end

	if source:IsA("Player") then
		local player = source :: Player
		local char = player.Character
		local entity: Instance? = nil
		if StatsManager.isRegistered(player) then
			entity = player
		elseif char and StatsManager.isRegistered(char) then
			entity = char
		end
		return player, char, entity
	end

	local sourceModel = if source:IsA("Model") then source else modelOf(source)
	local sourcePlayer = if sourceModel then Players:GetPlayerFromCharacter(sourceModel) else nil

	local entity: Instance? = nil
	if StatsManager.isRegistered(source) then
		entity = source
	elseif sourceModel and StatsManager.isRegistered(sourceModel) then
		entity = sourceModel
	elseif sourcePlayer and StatsManager.isRegistered(sourcePlayer) then
		entity = sourcePlayer
	end

	return sourcePlayer, sourceModel, entity
end

local function resolveStatic(name: string): any
	return (StatTypes.StaticStats :: any)[name]
end

	local function getEntityStatValue(entity: Instance?, statKey: any, queryOptions: any?): number
	if not entity or not statKey then
		return 0
	end
	local value = StatsManager.getStatValue(entity, statKey, queryOptions)
	return value or 0
end

local function getEntityStatValueByName(entity: Instance?, name: string, queryOptions: any?): number
	return getEntityStatValue(entity, resolveStatic(name), queryOptions)
end

	local function copyTable(source: { [any]: any }?): { [any]: any }
		local target: { [any]: any } = {}
		if not source then
			return target
		end
		for key, value in pairs(source) do
			target[key] = value
		end
		return target
	end

	local function buildResourceQueryOptions(eventName: string, poolType: any, stage: string, base: { [any]: any }?, overrides: { [any]: any }?)
		local meta = copyTable(base)
		meta.pool = poolType
		meta.stage = stage
		if overrides then
			for key, value in pairs(overrides) do
				meta[key] = value
			end
		end
		return {
			event = eventName,
			context = eventName,
			cacheKey = stage,
			metadata = meta,
			cacheEnabled = false,
			allowObservers = nil,
			instrument = nil,
			originalStat = poolType,
			overrideStat = nil,
		}
	end

	local function buildResourceSpendOptions(poolType: any, amount: number, stage: string, base: { [any]: any }?, overrides: { [any]: any }?)
		local meta = copyTable(base)
		meta.pool = poolType
		meta.stage = stage
		meta.baseCost = amount
		if overrides then
			for key, value in pairs(overrides) do
				meta[key] = value
			end
		end
		return {
			event = "resolveCombatCost",
			context = "resolveCombatCost",
			cacheKey = stage,
			metadata = meta,
			cacheEnabled = false,
			allowObservers = nil,
			instrument = nil,
			originalStat = poolType,
			overrideStat = nil,
		}
	end

local ARMOR_K = 100 -- tuning constant for armor diminishing returns

local function normalizeChance(v: number?): number
	if not v then
		return 0
	end
	if v > 1 then
		-- allow percent inputs like 5, 25, 100
		v = v / 100
	end
	return math.clamp(v, 0, 1)
end

local function roll(p: number): boolean
	local prob = math.clamp(p, 0, 1)
	if prob <= 0 then return false end
	if prob >= 1 then return true end
	return (math.random() < prob)
end

-- Main, extensible damage pipeline
function CombatService.applyDamageDetailed(
	target: Instance,
	baseAmount: number,
	source: Instance?,
	opts: DamageOptions?
): DamageResult
	local result: DamageResult = {
		dodged = false,
		crit = false,
		baseAmount = baseAmount,
		mitigated = 0,
		absorbed = 0,
		appliedToHealth = 0,
		finalAmount = 0,
		targetPlayer = nil,
		targetHumanoid = nil,
		sourcePlayer = nil,
		sourceModel = nil,
		sourceEntity = nil,
	}
	if baseAmount <= 0 then
		return result
	end

	local targetPlayer = playerFromTarget(target)
	result.targetPlayer = targetPlayer
	result.targetHumanoid = CombatService.getHumanoid(target)

	local targetModel = if target:IsA("Model") then target else modelOf(target)
	local targetEntity: Instance? = targetPlayer
	if not targetEntity and targetModel and StatsManager.isRegistered(targetModel) then
		targetEntity = targetModel
	end

	local sourcePlayer, sourceModel, sourceEntity = resolveSourceInfo(source)
	result.sourcePlayer = sourcePlayer
	result.sourceModel = sourceModel
	result.sourceEntity = sourceEntity

	local damageKind = (opts and opts.kind) or "generic"

	local effectiveSourceForStats = sourceEntity
	if not effectiveSourceForStats and sourcePlayer then
		effectiveSourceForStats = sourcePlayer
	elseif not effectiveSourceForStats and sourceModel and StatsManager.isRegistered(sourceModel) then
		effectiveSourceForStats = sourceModel
	end

	-- Pre-hit: dodge (target stat) if present
	if targetPlayer then
		local dodge = normalizeChance(getEntityStatValueByName(targetPlayer, "DodgeChance", {
			event = "preDamageQuery",
			metadata = {
				stat = "DodgeChance",
				phase = "avoidance",
				target = targetPlayer,
				source = sourceEntity,
			},
		}))
		if roll(dodge) then
			result.dodged = true
			return result
		end
	end

	local amount = baseAmount

	-- Attacker crit (optional, if stats exist)
	if opts == nil or opts.critAllowed ~= false then
		local critChance = normalizeChance(getEntityStatValueByName(effectiveSourceForStats, "CriticalHitChance", {
			event = "preDamageQuery",
			metadata = {
				stat = "CriticalHitChance",
				phase = "attack",
				target = targetEntity,
				source = effectiveSourceForStats,
			},
		}))
		local critDamage = getEntityStatValueByName(effectiveSourceForStats, "CriticalHitDamage", {
			event = "preDamageQuery",
			metadata = {
				stat = "CriticalHitDamage",
				phase = "attack",
				target = targetEntity,
				source = effectiveSourceForStats,
			},
		})
		if roll(critChance) then
			result.crit = true
			-- Interpret CriticalHitDamage flexibly:
			--   150 -> 1.5x (percent total)
			--   1.5 -> 1.5x (direct multiplier)
			--   0.5 -> 1.5x (bonus fraction)
			local multiplier: number
			if critDamage and critDamage > 0 then
				if critDamage > 3 then
					multiplier = critDamage / 100
				elseif critDamage >= 1 then
					multiplier = critDamage
				else
					multiplier = 1 + critDamage
				end
			else
				multiplier = 1.5
			end
			amount = amount * multiplier
		end
	end

	-- Mitigation (armor/reduction) if present
	if not (opts and opts.bypassArmor) then
		if targetPlayer then
			local damageReduction = getEntityStatValueByName(targetPlayer, "DamageReduction", {
				event = "preDamageQuery",
				metadata = {
					stat = "DamageReduction",
					phase = "mitigation",
					target = targetPlayer,
					source = sourceEntity,
				},
			})
			local dr = (damageReduction > 1) and (damageReduction / 100) or damageReduction
			local armor = getEntityStatValueByName(targetPlayer, "Armor", {
				event = "preDamageQuery",
				metadata = {
					stat = "Armor",
					phase = "mitigation",
					target = targetPlayer,
					source = sourceEntity,
				},
			})
			local armorFactor = (armor > 0) and (armor / (armor + ARMOR_K)) or 0
			local reduceFactor = math.clamp(dr + armorFactor, 0, 0.9)
			local reduced = amount * reduceFactor
			amount -= reduced
			result.mitigated = reduced
		end
	end

	-- Absorption (ManaShield) for players
	local resourceMetaBase = {
		target = targetEntity,
		targetPlayer = targetPlayer,
		targetModel = targetModel,
		targetHumanoid = result.targetHumanoid,
		source = sourceEntity,
		sourcePlayer = sourcePlayer,
		sourceModel = sourceModel,
		damageKind = damageKind,
		crit = result.crit,
		dodged = result.dodged,
		mitigated = result.mitigated,
	}

	if not (opts and opts.bypassShield) and targetEntity then
		local damageBeforeAbsorb = amount
		local shieldQuery = buildResourceQueryOptions("combatResourceQuery", StatTypes.PoolStats.ManaShield, "shield_check", resourceMetaBase, {
			incomingDamage = damageBeforeAbsorb,
		})
		local currentShield = StatsManager.getPoolCurrentValue(targetEntity, StatTypes.PoolStats.ManaShield, shieldQuery) or 0
		if currentShield > 0 then
			local absorb = math.min(currentShield, amount)
			if absorb > 0 then
				local shieldSpend = buildResourceSpendOptions(StatTypes.PoolStats.ManaShield, absorb, "shield_absorb", resourceMetaBase, {
					reason = "shield_absorb",
					incomingDamage = damageBeforeAbsorb,
					absorbAmount = absorb,
				})
				StatsManager.removeFromPool(targetEntity, StatTypes.PoolStats.ManaShield, absorb, shieldSpend)
				result.absorbed = absorb
				amount -= absorb
				if result.resourceMeta == nil then
					result.resourceMeta = { shield = nil, health = nil }
				end
				local resourceMeta = result.resourceMeta
				if resourceMeta then
					resourceMeta.shield = copyTable(shieldSpend.metadata)
				end
			end
		end
	end

	-- Apply to health or humanoid
	if targetPlayer then
		if amount > 0 then
			local healthSpend = buildResourceSpendOptions(StatTypes.PoolStats.Health, amount, "health_damage", resourceMetaBase, {
				reason = "damage",
				absorbed = result.absorbed,
				appliedAmount = amount,
			})
			StatsManager.removeFromPool(targetPlayer, StatTypes.PoolStats.Health, amount, healthSpend)
			result.appliedToHealth = amount
			result.finalAmount = amount
			if result.resourceMeta == nil then
				result.resourceMeta = { shield = nil, health = nil }
			end
			local resourceMeta = result.resourceMeta
			if resourceMeta then
				resourceMeta.health = copyTable(healthSpend.metadata)
			end
		end
	elseif targetEntity then
		if amount > 0 then
			local healthSpend = buildResourceSpendOptions(StatTypes.PoolStats.Health, amount, "health_damage", resourceMetaBase, {
				reason = "damage",
				absorbed = result.absorbed,
				appliedAmount = amount,
			})
			StatsManager.removeFromPool(targetEntity, StatTypes.PoolStats.Health, amount, healthSpend)
			result.appliedToHealth = amount
			result.finalAmount = amount
			if result.resourceMeta == nil then
				result.resourceMeta = { shield = nil, health = nil }
			end
			local resourceMeta = result.resourceMeta
			if resourceMeta then
				resourceMeta.health = copyTable(healthSpend.metadata)
			end
		end
	else
		if amount > 0 and result.targetHumanoid then
			result.targetHumanoid:TakeDamage(amount)
			result.appliedToHealth = amount
			result.finalAmount = amount
		end
	end

	-- Status effects (post-hit): roll and apply if provided and not dodged
	if not result.dodged and opts and opts.effects then
		local applied: { string } = {}
		for _, eff in ipairs(opts.effects) do
			local chance = (eff.chance ~= nil) and (eff.chance :: number) or 1
			if roll(chance) then
				local effectSource = source or sourceEntity or sourcePlayer or sourceModel
				if StatusEffectsService.apply(target, eff.id, effectSource, eff.params) then
					table.insert(applied, eff.id)
				end
			end
		end
		if #applied > 0 then
			result.effectsApplied = applied
		end
	end

	return result
end

-- Apply raw damage. Returns true if any damage was applied.
function CombatService.applyDamage(target: Instance, amount: number, source: Instance?): boolean
	local r = CombatService.applyDamageDetailed(target, amount, source, nil)
	return (r.finalAmount > 0) or (r.absorbed > 0)
end

return CombatService
