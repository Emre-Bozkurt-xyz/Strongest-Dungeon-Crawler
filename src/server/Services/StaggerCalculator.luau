--!strict
-- Stagger Calculator - Computes dynamic stagger thresholds based on stats and progression
-- Similar to AttributeMilestones pattern - defines formulas that scale with character stats

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Server = ServerScriptService.Server

local CharacterSpecRegistry = require(ReplicatedStorage.Shared.Characters.CharacterSpecRegistry)
local StatsManager = require(Server.Stats.StatsManager)
local AttributesManager = require(ServerScriptService.Server.Stats.AttributesManager)
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)
local AttributeTypes = require(ReplicatedStorage.Shared.AttributeTypes)

local StaggerCalculator = {}

-- Scaling formulas for stagger thresholds
-- These are applied ON TOP of base character spec values
local ScalingFormulas = {
	-- Threshold scales up with Armor (physical resistance)
	ThresholdFromArmor = function(armorValue: number): number
		-- Every 5 armor adds +2 to threshold
		return math.floor(armorValue / 5) * 2
	end,

	-- Duration can be reduced by Resilience/Tenacity stat
	DurationFromResilience = function(resilienceValue: number, baseDuration: number): number
		-- Every 20 resilience reduces duration by 10% (up to 50% reduction)
		local reductionPercent = math.min(0.5, (resilienceValue / 20) * 0.1)
		return baseDuration * (1 - reductionPercent)
	end,

	-- Cooldown can be reduced by high Dexterity (faster recovery)
	CooldownFromDexterity = function(dexterityValue: number, baseCooldown: number): number
		-- Every 25 dexterity reduces cooldown by 10% (up to 40% reduction)
		local reductionPercent = math.min(0.4, (dexterityValue / 25) * 0.1)
		return baseCooldown * (1 - reductionPercent)
	end,
}

-- Helper to safely get stat value with fallback
local function getStatValue(entityId: string, statKey: any): number
	local value = StatsManager.getStatValue(entityId, statKey)
	return value or 0
end

-- Compute dynamic stagger threshold for entity
function StaggerCalculator.computeThreshold(entityId: string, specId: string?): number
	-- Get base threshold from character spec
	local spec = CharacterSpecRegistry.get(specId or "PlayerCharacter")
	if not spec or not spec.stagger then
		return 50 -- Fallback default
	end

	local baseThreshold = spec.stagger.threshold

	-- Apply scaling from stats
	local armorValue = getStatValue(entityId, StatTypes.StaticStats.Armor)

	local armorBonus = ScalingFormulas.ThresholdFromArmor(armorValue)

	-- Final threshold = base + stat bonuses
	local finalThreshold = baseThreshold + armorBonus

	return math.floor(finalThreshold)
end

-- Compute dynamic stagger duration for entity
function StaggerCalculator.computeDuration(entityId: string, specId: string?): number
	local spec = CharacterSpecRegistry.get(specId or "PlayerCharacter")
	if not spec or not spec.stagger then
		return 1.5 -- Fallback default
	end

	local baseDuration = spec.stagger.duration

	-- Apply reduction from resilience (if stat exists)
	-- local resilienceValue = getStatValue(entityId, StatTypes.StaticStats.Resilience)
	-- local finalDuration = ScalingFormulas.DurationFromResilience(resilienceValue, baseDuration)

	-- For now, return base duration (add resilience stat later)
	return baseDuration
end

-- Compute dynamic stagger cooldown for entity
function StaggerCalculator.computeCooldown(entityId: string, specId: string?): number
	local spec = CharacterSpecRegistry.get(specId or "PlayerCharacter")
	if not spec or not spec.stagger then
		return 3.0 -- Fallback default
	end

	local baseCooldown = spec.stagger.cooldown

	-- Apply reduction from dexterity
	-- local dexterityValue = AttributesManager.getAttributeValue(entityId, AttributeTypes.Attributes.Dexterity)
	-- local finalCooldown = ScalingFormulas.CooldownFromDexterity(dexterityValue, baseCooldown)

	return baseCooldown
end

-- Compute max stack damage (guaranteed stagger threshold)
function StaggerCalculator.computeMaxStackDamage(entityId: string, specId: string?): number
	local spec = CharacterSpecRegistry.get(specId or "PlayerCharacter")
	if not spec or not spec.stagger then
		return 150 -- Fallback default
	end

	-- Max stack damage scales with regular threshold
	-- Typically 3x the normal threshold
	local threshold = StaggerCalculator.computeThreshold(entityId, specId)
	return threshold * 3
end

-- Compute all stagger values at once (more efficient)
function StaggerCalculator.computeAll(
	entityId: string,
	specId: string?
): {
	threshold: number,
	duration: number,
	cooldown: number,
	maxStackDamage: number,
}
	return {
		threshold = StaggerCalculator.computeThreshold(entityId, specId),
		duration = StaggerCalculator.computeDuration(entityId, specId),
		cooldown = StaggerCalculator.computeCooldown(entityId, specId),
		maxStackDamage = StaggerCalculator.computeMaxStackDamage(entityId, specId),
	}
end

-- Export scaling formulas for testing/debugging
StaggerCalculator.ScalingFormulas = ScalingFormulas

return StaggerCalculator
