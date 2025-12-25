--!strict
-- Combat utility to apply damage using entityId-based architecture
-- All damage flows through the Stats system using entityIds as the source of truth

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = game:GetService("ServerScriptService").Server

local StatTypes = require(ReplicatedStorage.Shared.StatTypes)
local StatsManager = require(Server.Stats.StatsManager)
local StatusEffectsService = require(script.Parent.Parent.StatusEffects.StatusEffectsService)
local AttackTypes = require(ReplicatedStorage.Shared.skills.AttackTypes)
local Networking = require(ReplicatedStorage.Shared.Networking)
local StaggerSystem = require(script.Parent.StaggerSystem)
local Registrar = require(script.Parent.Registrar)

local dispatcher = Networking.server() :: any

local CombatService = {}

export type DamageEffect = { id: string, chance: number?, params: any? }

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
	targetEntity: string,
	source: string,
	-- IDs of any status effects that were applied by this damage instance
	effectsApplied: { string }?,
	resourceMeta: ResourceMetaSnapshot?,
}

-- Extended result for damage numbers and UI
export type AttackResult = DamageResult & {
	byType: { [string]: number }, -- Damage breakdown by type (Physical, Fire, etc)
	blocked: boolean, -- Was attack blocked by shield/guard
	totalDamage: number, -- Sum of all damage types
	staggerApplied: boolean?, -- Was stagger applied to target
}

local function resolveStatic(name: string): any
	return (StatTypes.StaticStats :: any)[name]
end

local function getEntityStatValue(entityId: string, statKey: any, queryOptions: any?): number
	if not entityId or not statKey then
		return 0
	end
	local value = StatsManager.getStatValue(entityId, statKey, queryOptions)
	return value or 0
end

local function getEntityStatValueByName(entityId: string, name: string, queryOptions: any?): number
	return getEntityStatValue(entityId, resolveStatic(name), queryOptions)
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

local function buildResourceQueryOptions(
	eventName: string,
	poolType: any,
	stage: string,
	base: { [any]: any }?,
	overrides: { [any]: any }?
)
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

local function buildResourceSpendOptions(
	poolType: any,
	amount: number,
	stage: string,
	base: { [any]: any }?,
	overrides: { [any]: any }?
)
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
	if prob <= 0 then
		return false
	end
	if prob >= 1 then
		return true
	end
	return (math.random() < prob)
end

-- Internal damage pipeline (private - use applyAttack for all damage)
local function _applyDamageInternal(
	targetEntityId: string, -- entityId only
	baseAmount: number,
	sourceEntityId: string, -- entityId only
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
		source = sourceEntityId,
		targetEntity = targetEntityId,
	}
	if baseAmount <= 0 then
		return result
	end

	if not targetEntityId or targetEntityId == "" then
		warn("[CombatService] Invalid targetEntityId provided")
		return result
	end

	local damageKind = (opts and opts.kind) or "generic"
	local amount = baseAmount

	-- Pre-hit: dodge (target stat) if present
	local dodge = normalizeChance(getEntityStatValueByName(targetEntityId, "DodgeChance", {
		event = "preDamageQuery",
		metadata = {
			stat = "DodgeChance",
			phase = "avoidance",
			target = targetEntityId,
			source = sourceEntityId,
		},
	}))
	if roll(dodge) then
		result.dodged = true
		return result
	end

	-- Attacker crit (optional, if stats exist)
	if opts == nil or opts.critAllowed ~= false then
		local critChance = normalizeChance(getEntityStatValueByName(sourceEntityId, "CriticalHitChance", {
			event = "preDamageQuery",
			metadata = {
				stat = "CriticalHitChance",
				phase = "attack",
				target = targetEntityId,
				source = sourceEntityId,
			},
		}))
		local critDamage = getEntityStatValueByName(sourceEntityId, "CriticalHitDamage", {
			event = "preDamageQuery",
			metadata = {
				stat = "CriticalHitDamage",
				phase = "attack",
				target = targetEntityId,
				source = sourceEntityId,
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
		local damageReduction = getEntityStatValueByName(targetEntityId, "DamageReduction", {
			event = "preDamageQuery",
			metadata = {
				stat = "DamageReduction",
				phase = "mitigation",
				target = targetEntityId,
				source = sourceEntityId,
			},
		})
		local dr = (damageReduction > 1) and (damageReduction / 100) or damageReduction
		local armor = getEntityStatValueByName(targetEntityId, "Armor", {
			event = "preDamageQuery",
			metadata = {
				stat = "Armor",
				phase = "mitigation",
				target = targetEntityId,
				source = sourceEntityId,
			},
		})
		local armorFactor = (armor > 0) and (armor / (armor + ARMOR_K)) or 0
		local reduceFactor = math.clamp(dr + armorFactor, 0, 0.9)
		local reduced = amount * reduceFactor
		amount -= reduced
		result.mitigated = reduced
	end

	-- Absorption (ManaShield) for players
	local resourceMetaBase = {
		target = targetEntityId,
		source = sourceEntityId,
		damageKind = damageKind,
		crit = result.crit,
		dodged = result.dodged,
		mitigated = result.mitigated,
	}

	if not (opts and opts.bypassShield) then
		local damageBeforeAbsorb = amount
		local shieldQuery = buildResourceQueryOptions(
			"combatResourceQuery",
			StatTypes.PoolStats.ManaShield,
			"shield_check",
			resourceMetaBase,
			{
				incomingDamage = damageBeforeAbsorb,
			}
		)
		local currentShield = StatsManager.getPoolCurrentValue(
			targetEntityId,
			StatTypes.PoolStats.ManaShield,
			shieldQuery
		) or 0
		if currentShield > 0 then
			local absorb = math.min(currentShield, amount)
			if absorb > 0 then
				local shieldSpend = buildResourceSpendOptions(
					StatTypes.PoolStats.ManaShield,
					absorb,
					"shield_absorb",
					resourceMetaBase,
					{
						reason = "shield_absorb",
						incomingDamage = damageBeforeAbsorb,
						absorbAmount = absorb,
					}
				)
				StatsManager.removeFromPool(targetEntityId, StatTypes.PoolStats.ManaShield, absorb, shieldSpend)
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
	if amount > 0 then
		local healthSpend =
			buildResourceSpendOptions(StatTypes.PoolStats.Health, amount, "health_damage", resourceMetaBase, {
				reason = "damage",
				absorbed = result.absorbed,
				appliedAmount = amount,
			})
		StatsManager.removeFromPool(targetEntityId, StatTypes.PoolStats.Health, amount, healthSpend)
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

	-- Status effects (post-hit): roll and apply if provided and not dodged
	if not result.dodged and opts and opts.effects then
		local applied: { string } = {}
		for _, eff in ipairs(opts.effects) do
			local chance = (eff.chance ~= nil) and (eff.chance :: number) or 1
			if roll(chance) then
				if StatusEffectsService.apply(targetEntityId, eff.id, sourceEntityId, eff.params) then
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

-- ============================================================================
-- ATTACK COMPOSITION SYSTEM
-- ============================================================================

-- Apply a single damage packet (internal helper)
local function applyDamagePacket(
	targetEntityId: string,
	packet: AttackTypes.AttackPacket,
	sourceEntityId: string,
	metadata: AttackTypes.AttackMetadata
): DamageResult
	local opts: DamageOptions = {
		kind = packet.damageType or "generic",
		element = packet.damageType,
		critAllowed = metadata.isCrit ~= false, -- allow crit unless explicitly disabled
		bypassShield = false,
		bypassArmor = packet.penetration and packet.penetration >= 1.0,
		effects = nil,
	}

	return _applyDamageInternal(targetEntityId, packet.amount or 0, sourceEntityId, opts)
end

-- Broadcast hit event to clients for damage numbers
local function broadcastHit(
	sourceEntityId: string,
	targetEntityId: string,
	attackResult: AttackResult,
	skillId: string?
)
	print(
		`[CombatService] Broadcasting hit: source={sourceEntityId}, target={targetEntityId}, total={attackResult.totalDamage}, byType=`,
		attackResult.byType
	)

	dispatcher:emit("HitEvent", {
		sourceId = sourceEntityId,
		targetId = targetEntityId,
		result = attackResult,
		skillId = skillId, -- Pass skill ID for sound selection
		timestamp = os.clock(),
	})
end

-- Process attack composition: damage packets, status effects, heals, drains
function CombatService.applyAttack(
	targetEntityId: string,
	attack: AttackTypes.AttackContext,
	sourceEntityId: string
): AttackResult
	-- Initialize attack result
	local attackResult: AttackResult = {
		dodged = false,
		crit = attack.metadata.isCrit or false,
		baseAmount = 0,
		mitigated = 0,
		absorbed = 0,
		appliedToHealth = 0,
		finalAmount = 0,
		targetEntity = targetEntityId,
		source = sourceEntityId,
		effectsApplied = {} :: { string },
		byType = {},
		blocked = false,
		totalDamage = 0,
	}

	for _, packet in attack.packets do
		if packet.type == "damage" then
			-- Apply damage packet with type-specific logic
			local result = applyDamagePacket(targetEntityId, packet, sourceEntityId, attack.metadata)

			-- Accumulate damage by type
			local damageType = packet.damageType or "Physical"
			attackResult.byType[damageType] = (attackResult.byType[damageType] or 0) + result.finalAmount

			-- Aggregate overall stats
			attackResult.totalDamage = attackResult.totalDamage + result.finalAmount
			attackResult.mitigated = attackResult.mitigated + result.mitigated
			attackResult.absorbed = attackResult.absorbed + result.absorbed
			attackResult.appliedToHealth = attackResult.appliedToHealth + result.appliedToHealth
			attackResult.finalAmount = attackResult.finalAmount + result.finalAmount
			attackResult.dodged = attackResult.dodged or result.dodged

			-- Track base amount from first packet
			if attackResult.baseAmount == 0 then
				attackResult.baseAmount = result.baseAmount
			end
		elseif packet.type == "effect" then
			-- Roll chance and apply status effect
			if not packet.effectId then
				continue
			end

			local shouldApply = true
			if packet.chance then
				shouldApply = roll(packet.chance)
			end

			if shouldApply then
				StatusEffectsService.apply(targetEntityId, packet.effectId, sourceEntityId, packet.params)
				if attackResult.effectsApplied then
					table.insert(attackResult.effectsApplied, packet.effectId)
				end
			end
		elseif packet.type == "heal" then
			-- Heal packet: restore pool value
			local poolType = (packet.poolType or StatTypes.PoolStats.Health) :: any
			local amount = packet.amount or 0
			if amount > 0 then
				StatsManager.addToPool(targetEntityId, poolType, amount)
			end
		elseif packet.type == "drain" then
			-- Drain packet: remove from target, add to source
			local poolType = (packet.poolType or StatTypes.PoolStats.Health) :: any
			local amount = packet.amount or 0
			if amount > 0 then
				StatsManager.removeFromPool(targetEntityId, poolType, amount, {
					metadata = {
						source = sourceEntityId,
						skillId = attack.metadata.skillId,
						reason = "drain_packet",
					},
				})
				StatsManager.addToPool(sourceEntityId, poolType, amount)
			end
			-- Note: knockback packet type not yet implemented
		end
	end

	-- Apply stagger if damage was dealt (before broadcasting so client gets the flag)
	if attackResult.totalDamage > 0 then
		-- Resolve specId from entity's CharacterSpecId attribute, fallback to PlayerCharacter
		local specId = "PlayerCharacter"
		local targetModel = Registrar.getEntityById(targetEntityId)
		if targetModel then
			local attributeSpecId = targetModel:GetAttribute("CharacterSpecId")
			if attributeSpecId and type(attributeSpecId) == "string" then
				specId = attributeSpecId
			elseif not Registrar.isPlayerEntity(targetEntityId) then
				-- NPC without attribute - use model name as fallback
				specId = targetModel.Name
			end
		end

		attackResult.staggerApplied =
			StaggerSystem.tryStagger(targetEntityId, attackResult.totalDamage, sourceEntityId, specId)
	end

	-- Broadcast hit event to clients for damage numbers
	if
		attackResult.totalDamage > 0
		or attackResult.dodged
		or (attackResult.effectsApplied and #attackResult.effectsApplied > 0)
	then
		broadcastHit(sourceEntityId, targetEntityId, attackResult, attack.metadata.skillId)
	end

	return attackResult
end

return CombatService
