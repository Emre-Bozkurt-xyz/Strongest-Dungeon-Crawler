--!strict
-- Simple combat utility to apply damage to Stats (players) or Humanoids (NPC fallback)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StatTypes = require(ReplicatedStorage.Shared.StatTypes)
local StatsManager = require(script.Parent:WaitForChild("StatsManager"))
local StatusEffectsService = require(script.Parent:WaitForChild("StatusEffectsService"))

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
	-- IDs of any status effects that were applied by this damage instance
	effectsApplied: { string }?,
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

local function resolveStatic(name: string): any
	return (StatTypes.StaticStats :: any)[name]
end

local function getStatValue(stats: any, key: any): number
	if not stats or not key then
		return 0
	end
	local s = stats[key]
	if s and s.getValue then
		return s:getValue(stats)
	end
	return 0
end

local function getStatValueByName(stats: any, name: string): number
	return getStatValue(stats, resolveStatic(name))
end

local ARMOR_K = 100 -- tuning constant for armor diminishing returns

local function roll(p: number): boolean
	if p <= 0 then
		return false
	end
	if p >= 1 then
		return true
	end
	return (math.random() < p)
end

-- Main, extensible damage pipeline
function CombatService.applyDamageDetailed(
	target: Instance,
	baseAmount: number,
	source: Player?,
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
	}
	if baseAmount <= 0 then
		return result
	end

	local targetPlayer = playerFromTarget(target)
	result.targetPlayer = targetPlayer
	result.targetHumanoid = CombatService.getHumanoid(target)

	-- Pre-hit: dodge (target stat) if present
	if targetPlayer then
		local tStats = StatsManager.getAllStats(targetPlayer)
		local dodge = getStatValueByName(tStats, "DodgeChance")
		if roll(dodge) then
			result.dodged = true
			return result
		end
	end

	local amount = baseAmount

	-- Attacker crit (optional, if stats exist)
	if opts == nil or opts.critAllowed ~= false then
		local sStats = source and StatsManager.getAllStats(source) or nil
		local critChance = getStatValueByName(sStats, "CriticalHitChance")
		local critDamage = getStatValueByName(sStats, "CriticalHitDamage")
		if roll(critChance) then
			result.crit = true
			local bonus = (critDamage > 0) and critDamage or 0.5 -- defaults to +50% if not configured
			amount = amount * (1 + bonus)
		end
	end

	-- Mitigation (armor/reduction) if present
	if not (opts and opts.bypassArmor) then
		if targetPlayer then
			local tStats2 = StatsManager.getAllStats(targetPlayer)
			local damageReduction = getStatValueByName(tStats2, "DamageReduction")
			local armor = getStatValueByName(tStats2, "Armor")
			local armorFactor = (armor > 0) and (armor / (armor + ARMOR_K)) or 0
			local reduceFactor = math.clamp(damageReduction + armorFactor, 0, 0.9)
			local reduced = amount * reduceFactor
			amount -= reduced
			result.mitigated = reduced
		end
	end

	-- Absorption (ManaShield) for players
	if not (opts and opts.bypassShield) then
		if targetPlayer then
			local stats = StatsManager.getAllStats(targetPlayer)
			local shield = stats and stats[StatTypes.PoolStats.ManaShield]
			if shield and shield.getCurrentValue then
				local cur = shield:getCurrentValue()
				if cur > 0 then
					local absorb = math.min(cur, amount)
					if absorb > 0 then
						StatsManager.removeFromPool(targetPlayer, StatTypes.PoolStats.ManaShield, absorb)
						result.absorbed = absorb
						amount -= absorb
					end
				end
			end
		end
	end

	-- Apply to health or humanoid
	if targetPlayer then
		if amount > 0 then
			StatsManager.removeFromPool(targetPlayer, StatTypes.PoolStats.Health, amount)
			result.appliedToHealth = amount
			result.finalAmount = amount
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
				if StatusEffectsService.apply(target, eff.id, source, eff.params) then
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
function CombatService.applyDamage(target: Instance, amount: number, source: Player?): boolean
	local r = CombatService.applyDamageDetailed(target, amount, source, nil)
	return (r.finalAmount > 0) or (r.absorbed > 0)
end

return CombatService
