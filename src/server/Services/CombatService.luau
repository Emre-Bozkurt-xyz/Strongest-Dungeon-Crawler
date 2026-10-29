--!strict
-- Combat utility to apply damage using entityId-based architecture
-- All damage flows through the Stats system using entityIds as the source of truth

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = game:GetService("ServerScriptService").Server

local StatTypes = require(ReplicatedStorage.Shared.StatTypes)
local StatsManager = require(Server.Stats.StatsManager)
local StatusEffectsService = require(script.Parent.Parent.StatusEffects.StatusEffectsService)
local AttackTypes = require(ReplicatedStorage.Shared.skills.AttackTypes)
local Networking = require(ReplicatedStorage.Shared.Networking)
local StaggerSystem = require(script.Parent.StaggerSystem)
local Registrar = require(script.Parent.Registrar)
local MovementService = require(Server.Movement.MovementService)
local MovementSpec = require(ReplicatedStorage.Shared.Movement.MovementSpec)
local Clock = require(ReplicatedStorage.Shared.Time.Clock)
local DebugConfig = require(ReplicatedStorage.Shared.Debug.DebugConfig)

local dispatcher = Networking.server() :: any

local CombatService = {}

export type HitListener = (
	sourceEntityId: string,
	targetEntityId: string,
	result: AttackResult,
	metadata: AttackTypes.AttackMetadata
) -> ()

local hitListeners: { HitListener } = {}

-- Called after an attack has landed on a target and dealt damage. For systems that react to hits
-- (mastery progress) without CombatService knowing about them.
function CombatService.onHit(listener: HitListener)
	table.insert(hitListeners, listener)
end

-- What an attack hook sees: one attack, about to land on one target. Hooks may change it in place
-- -- scale damage packets, add effect packets, set a packet's crit chance bonus or penetration,
-- scale knockback, set `metadata.staggerScale` -- and must not yield.
export type AttackHookContext = {
	sourceId: string,
	targetId: string,
	packets: { AttackTypes.AttackPacket },
	metadata: AttackTypes.AttackMetadata,
}

export type AttackHook = (ctx: AttackHookContext) -> ()

local attackHooks: { AttackHook } = {}

-- Called for every attack before it is applied, with the packets copied for that target, so
-- systems that change attacks by who is attacking or who is hit (passives) do so without the skills
-- or CombatService knowing about them. One attack context is shared by every target a swing
-- reaches; the copy keeps a change aimed at one target from leaking into the next.
function CombatService.addAttackHook(hook: AttackHook)
	table.insert(attackHooks, hook)
end

export type DamageEffect = { id: string, chance: number?, params: any? }

export type DamageOptions = {
	kind: string?, -- "physical" | "magic" | "true" | custom
	element: string?, -- e.g., fire, ice
	critAllowed: boolean?,
	critChanceBonus: number?, -- percentage points added to the attacker's crit chance
	critDamageBonus: number?, -- added to the crit multiplier
	resistancePenetration: number?, -- percentage points of the target's resistance ignored
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
	-- Damage types of the packets that crit, for reactions to a crit of a kind ("fire crits ignite").
	-- Server-only.
	critTypes: { [string]: boolean }?,
	staggerApplied: boolean?, -- Was stagger applied to target
	knockback: Knockback?, -- Push applied to the target, resolved to a world direction
	-- Health the target actually lost: `appliedToHealth` is what was dealt, which overshoots on a
	-- killing blow. Server-only (not broadcast); mastery shares XP by it.
	healthRemoved: number?,
}

export type Knockback = {
	direction: Vector3,
	distance: number,
	duration: number?,
}

local function rootOf(entityId: string): BasePart?
	local entity = Registrar.getEntityById(entityId)
	return entity and entity:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Straight away from the attacker, along the ground. Falls back to the attacker's facing when the
-- two are stacked on top of each other.
local function awayFromSource(sourceEntityId: string, targetEntityId: string): Vector3?
	local sourceRoot = rootOf(sourceEntityId)
	local targetRoot = rootOf(targetEntityId)
	if not sourceRoot or not targetRoot then
		return nil
	end
	local delta = targetRoot.Position - sourceRoot.Position
	local flat = Vector3.new(delta.X, 0, delta.Z)
	if flat.Magnitude < 1e-3 then
		local look = sourceRoot.CFrame.LookVector
		flat = Vector3.new(look.X, 0, look.Z)
	end
	return if flat.Magnitude > 1e-3 then flat.Unit else nil
end

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

-- Elements are mitigated by resistance, not armor (armor is a physical defence). Percentage points,
-- capped at MAX_RESISTANCE; raising the cap is for classes and unique gear, never trees
-- (progression-direction.md, attunement content rules).
local MAX_RESISTANCE = 75
local RESISTANCE_STAT: { [string]: string } = {
	Fire = "FireResistance",
	Frost = "FrostResistance",
}
local PENETRATION_STAT: { [string]: string } = {
	Fire = "FirePenetration",
	Frost = "FrostPenetration",
}

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
		}) + (if opts and opts.critChanceBonus then opts.critChanceBonus else 0))
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
			multiplier += if opts and opts.critDamageBonus then opts.critDamageBonus else 0
			amount = amount * multiplier
		end
	end

	local element = opts and opts.element
	local resistanceStat = if element then RESISTANCE_STAT[element] else nil
	if resistanceStat then
		-- An element: resisted by its resistance, less what the attacker penetrates. Penetration only
		-- lowers resistance to zero; it never turns resistance into a weakness.
		local resistance = math.min(getEntityStatValueByName(targetEntityId, resistanceStat), MAX_RESISTANCE)
		local penetrationStat = PENETRATION_STAT[element :: string]
		local penetration = (if penetrationStat then getEntityStatValueByName(sourceEntityId, penetrationStat) else 0)
			+ (if opts and opts.resistancePenetration then opts.resistancePenetration else 0)
		if resistance > 0 then
			resistance = math.max(0, resistance - penetration)
		end
		local resisted = amount * resistance / 100
		amount -= resisted
		result.mitigated = resisted
	elseif not (opts and opts.bypassArmor) then
		-- Mitigation (armor/reduction) if present
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
		critChanceBonus = packet.critChanceBonus,
		critDamageBonus = packet.critDamageBonus,
		resistancePenetration = packet.resistancePenetration,
		bypassShield = false,
		bypassArmor = packet.penetration and packet.penetration >= 1.0,
		effects = nil,
	}

	return _applyDamageInternal(targetEntityId, packet.amount or 0, sourceEntityId, opts)
end

-- Players a hit is worth telling about: everyone near the target, plus the two involved wherever
-- they are. Hit events drive damage numbers, flashes and stagger, none of which anyone farther
-- away can see.
local HIT_RELEVANCE_RADIUS = 150

local function hitAudience(sourceEntityId: string, targetEntityId: string): { Player }
	local audience: { Player } = {}
	local included: { [Player]: true } = {}
	local function include(player: Player?)
		if player and not included[player] then
			included[player] = true
			table.insert(audience, player)
		end
	end
	include(Registrar.getPlayerById(sourceEntityId))
	include(Registrar.getPlayerById(targetEntityId))

	local target = Registrar.getEntityById(targetEntityId)
	local targetRoot = target and target:FindFirstChild("HumanoidRootPart") :: BasePart?
	if targetRoot then
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and (root.Position - targetRoot.Position).Magnitude <= HIT_RELEVANCE_RADIUS then
				include(player)
			end
		end
	end
	return audience
end

-- Broadcast the outcome of a hit for damage numbers, flashes and stagger. Only what clients draw;
-- the internal breakdown (mitigation, absorption, mediator metadata) stays on the server. `effectId`
-- marks a status's own damage (a burn's tick), which clients may draw but should not react to as a
-- strike.
local function broadcastHit(
	sourceEntityId: string,
	targetEntityId: string,
	attackResult: AttackResult,
	skillId: string?,
	effectId: string?
)
	if DebugConfig.isEnabled("combat") then
		print(
			`[CombatService] Broadcasting hit: source={sourceEntityId}, target={targetEntityId}, total={attackResult.totalDamage}, byType=`,
			attackResult.byType
		)
	end

	local audience = hitAudience(sourceEntityId, targetEntityId)
	if #audience == 0 then
		return
	end
	dispatcher:emit("HitEvent", {
		sourceId = sourceEntityId,
		targetId = targetEntityId,
		skillId = skillId,
		effectId = effectId,
		result = {
			totalDamage = attackResult.totalDamage,
			byType = attackResult.byType,
			crit = attackResult.crit,
			dodged = attackResult.dodged,
			blocked = attackResult.blocked,
			staggerApplied = attackResult.staggerApplied,
			knockback = attackResult.knockback,
		},
	}, {
		targets = audience,
	})
end

-- Process attack composition: damage packets, status effects, heals, drains
function CombatService.applyAttack(
	targetEntityId: string,
	attack: AttackTypes.AttackContext,
	sourceEntityId: string
): AttackResult
	if #attackHooks > 0 then
		local packets: { AttackTypes.AttackPacket } = {}
		for _, packet in ipairs(attack.packets) do
			table.insert(packets, table.clone(packet))
		end
		local copy: AttackTypes.AttackContext = {
			packets = packets,
			sourceId = attack.sourceId,
			metadata = table.clone(attack.metadata),
		}
		local ctx: AttackHookContext = {
			sourceId = sourceEntityId,
			targetId = targetEntityId,
			packets = copy.packets,
			metadata = copy.metadata,
		}
		for _, hook in ipairs(attackHooks) do
			local ok, err = pcall(hook :: any, ctx)
			if not ok then
				warn("[CombatService] attack hook failed:", err)
			end
		end
		attack = copy
	end

	local invuln, _ = StatusEffectsService.hasBlockingEffect(targetEntityId, "damage")
	local healthBefore = StatsManager.getPoolCurrentValue(targetEntityId, StatTypes.PoolStats.Health)
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
			if invuln then
				attackResult.blocked = true
				attackResult.dodged = true
				continue
			end
			-- Apply damage packet with type-specific logic
			local result = applyDamagePacket(targetEntityId, packet, sourceEntityId, attack.metadata)

			-- Accumulate damage by type
			local damageType = packet.damageType or "Physical"
			attackResult.byType[damageType] = (attackResult.byType[damageType] or 0) + result.finalAmount
			if result.crit then
				attackResult.crit = true
				local critTypes = attackResult.critTypes or {}
				critTypes[damageType] = true
				attackResult.critTypes = critTypes
			end

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

			if invuln and StatusEffectsService.isHarmful(packet.effectId) then
				attackResult.blocked = true
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
		elseif packet.type == "knockback" then
			-- Damage packets come first, so a dodge is already known: a dodged blow moves no one.
			if invuln or attackResult.dodged then
				continue
			end
			local distance = packet.distance or 0
			local direction = packet.direction or awayFromSource(sourceEntityId, targetEntityId)
			if distance > 0 and direction then
				attackResult.knockback = {
					direction = direction,
					distance = distance,
					duration = packet.duration,
				}
			end
		end
	end

	local knockback = attackResult.knockback
	if knockback and not Registrar.isPlayerEntity(targetEntityId) then
		MovementService.applyKnockback(
			targetEntityId,
			MovementSpec.buildKnockbackSpec({
				startTime = Clock.localNow(),
				direction = knockback.direction,
				distance = knockback.distance,
				duration = knockback.duration,
			})
		)
	end

	-- Apply stagger if damage was dealt (before broadcasting so client gets the flag). A status's own
	-- damage (a burn's tick) never staggers: ticks would keep a target staggered between blows.
	if attackResult.totalDamage > 0 and attack.metadata.effectId == nil then
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

		local staggerScale = attack.metadata.staggerScale
		local staggerDamage = attackResult.totalDamage * (if type(staggerScale) == "number" then staggerScale else 1)
		attackResult.staggerApplied = staggerDamage > 0
			and StaggerSystem.tryStagger(targetEntityId, staggerDamage, sourceEntityId, specId)
	end

	-- Broadcast hit event to clients for damage numbers
	if
		attackResult.totalDamage > 0
		or attackResult.dodged
		or (attackResult.effectsApplied and #attackResult.effectsApplied > 0)
	then
		broadcastHit(
			sourceEntityId,
			targetEntityId,
			attackResult,
			attack.metadata.skillId,
			attack.metadata.effectId
		)
	end

	if attackResult.totalDamage > 0 then
		local healthAfter = StatsManager.getPoolCurrentValue(targetEntityId, StatTypes.PoolStats.Health)
		if healthBefore and healthAfter then
			attackResult.healthRemoved = math.max(0, healthBefore - healthAfter)
		end
		for _, listener in ipairs(hitListeners) do
			task.spawn(listener, sourceEntityId, targetEntityId, attackResult, attack.metadata)
		end
	end

	return attackResult
end

return CombatService
