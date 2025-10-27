--!strict
-- Shared configuration for player attributes system
-- This file defines all available attributes and their properties

local Attribute = require(game.ReplicatedStorage.Shared.AttributeClass)
local AttributeTypes = require(game.ReplicatedStorage.Shared.AttributeTypes)
local StatTypes = require(game.ReplicatedStorage.Shared.StatTypes)
local ModifierFactories = require(game.ReplicatedStorage.Shared.Modifiers.Factories)

-- Re-export the main types from AttributeTypes (single source of truth)
export type PlayerAttributes = AttributeTypes.PlayerAttributes
export type AttributeType = AttributeTypes.AttributeType
export type AttributeConfig = AttributeTypes.AttributeConfig
export type AttributeModifier = AttributeTypes.AttributeModifier

local AttributesConfig = {}

-- Default attribute configurations (using enum-like constants)
AttributesConfig.DEFAULT_ATTRIBUTES = {
	[AttributeTypes.Attributes.Strength] = {
		baseValue = 0,
		description = AttributeTypes.Descriptions.Strength,
	},
	[AttributeTypes.Attributes.Defense] = {
		baseValue = 0,
		description = AttributeTypes.Descriptions.Defense,
	},
	[AttributeTypes.Attributes.Dexterity] = {
		baseValue = 0,
		description = AttributeTypes.Descriptions.Dexterity,
	},
	[AttributeTypes.Attributes.Intelligence] = {
		baseValue = 0,
		description = AttributeTypes.Descriptions.Intelligence,
	},
	[AttributeTypes.Attributes.Perception] = {
		baseValue = 0,
		description = AttributeTypes.Descriptions.Perception,
	},
}

AttributesConfig.DefaultAttributePoints = 1000

-- Attribute limits
AttributesConfig.MIN_ATTRIBUTE_VALUE = 0
AttributesConfig.MAX_ATTRIBUTE_VALUE = 999

-- ========================================
-- SCALING FORMULAS
-- ========================================

-- Define the scaling rates for each relationship
AttributesConfig.ScalingFormulas = {
	Intelligence = {
		MagicDamageFromValue = function(intelligenceValue: number): number
			-- Staged scaling: First 10 points at 1.5x, next 10 at 2.0x, rest at 2.5x
			local total = 0
			local remainingPoints = intelligenceValue

			-- Stage 1: First 10 points at 1.5x rate
			if remainingPoints > 0 then
				local pointsInThisStage = math.min(remainingPoints, 10)
				total += pointsInThisStage * 1.5
				remainingPoints -= pointsInThisStage
			end

			-- Stage 2: Next 10 points (11-20) at 2.0x rate
			if remainingPoints > 0 then
				local pointsInThisStage = math.min(remainingPoints, 10)
				total += pointsInThisStage * 2.0
				remainingPoints -= pointsInThisStage
			end

			-- Stage 3: Remaining points (21+) at 2.5x rate
			if remainingPoints > 0 then
				total += remainingPoints * 2.5
			end

			return total
		end,
		ManaFromValue = function(intelligenceValue: number): number
			-- Every 5th point of Intelligence gives +5 Mana
			return math.floor(intelligenceValue / 5) * 5
		end,
	},
	Strength = {
		PhysicalDamageFromValue = function(strengthValue: number): number
			-- Every 2nd point of Strength gives +1 Physical Damage
			return math.floor(strengthValue / 2)
		end,
	},
}

-- ========================================
-- SCALING RELATIONSHIPS
-- ========================================

local StatsManager = require(script.Parent.Parent.StatsManager)
local function addOrUpdateScalingModifier(player: Player, statName: StatTypes.StatType, modifierId: string, value: number, description: string)
	
	if StatsManager.hasModifier(player, statName, modifierId) then
		StatsManager.updateModifier(player, statName, modifierId, value)
	else
		local modifier = ModifierFactories.flatAdd({
			sourceId = modifierId,
			amount = value,
			description = description,
			tags = { "attribute", "scaling" },
			stackGroup = modifierId,
		})
		StatsManager.addModifier(player, statName, modifier)
	end
end

-- Define how each attribute scales different stats
AttributesConfig.AttributeMilestones = {
	{
		attribute = AttributeTypes.Attributes.Intelligence,
		applyScaling = function(player: Player, intelligenceValue: number)
			local newValue = AttributesConfig.ScalingFormulas.Intelligence.MagicDamageFromValue(intelligenceValue)
			addOrUpdateScalingModifier(player, StatTypes.StaticStats.MagicDamage, "IntelligenceScaling", newValue, "Increased Magic Damage from Intelligence")
		end,
	},
	{
		attribute = AttributeTypes.Attributes.Intelligence,
		applyScaling = function(player: Player, intelligenceValue: number)
			local newValue = AttributesConfig.ScalingFormulas.Intelligence.ManaFromValue(intelligenceValue)
			addOrUpdateScalingModifier(player, StatTypes.PoolStats.Mana, "IntelligenceManaScaling", newValue, "Increased Mana from Intelligence")
		end,
	},
	{
		attribute = AttributeTypes.Attributes.Strength,
		applyScaling = function(player: Player, strengthValue: number)
			local newValue = AttributesConfig.ScalingFormulas.Strength.PhysicalDamageFromValue(strengthValue)
			addOrUpdateScalingModifier(player, StatTypes.StaticStats.PhysicalDamage, "StrengthScaling", newValue, "Increased Physical Damage from Strength")
		end,
	},
	-- Perception drives reveal radius and info tier
	{
		attribute = AttributeTypes.Attributes.Perception,
		applyScaling = function(player: Player, perceptionValue: number)
			-- Example mapping: distance grows sublinearly; tier grows at breakpoints
			-- Distance: base 60 + sqrt(perception)*6 studs
			local dist = 60 + math.sqrt(math.max(perceptionValue, 0)) * 6
			-- Use modifier as delta-from-base to avoid double-counting the default base value
			local stat = StatsManager.getStat(player, StatTypes.StaticStats.PerceptionDistance)
			local base = 0
			if stat and (stat :: any).getBaseValue then
				base = (stat :: any):getBaseValue()
			end
			local delta = math.max(0, dist - base)
			addOrUpdateScalingModifier(player, StatTypes.StaticStats.PerceptionDistance, "PerceptionDistanceFromPerception", delta, "Reveal distance from Perception")

			-- Tier: 0(<1), 1(>=1), 2(>=10), 3(>=25), 4(>=50), 5(>=100)
			local tier = 0
			if perceptionValue >= 1 then
				tier = 1
			end
			if perceptionValue >= 10 then
				tier = 2
			end
			if perceptionValue >= 25 then
				tier = 3
			end
			if perceptionValue >= 50 then
				tier = 4
			end
			if perceptionValue >= 100 then
				tier = 5
			end
			addOrUpdateScalingModifier(player, StatTypes.StaticStats.PerceptionTier, "PerceptionTierFromPerception", tier, "Reveal tier from Perception")
		end,
	},
} :: { 
	attribute: AttributeType, 
	applyScaling: (player: Player, attributeValue: number) -> () 
}

-- Helper function to create a new set of attributes using Attribute classes
function AttributesConfig.createDefaultAttributes(): PlayerAttributes
	local attributes = {} :: any

	-- Create attribute instances using enum constants
	for attributeName, config in pairs(AttributesConfig.DEFAULT_ATTRIBUTES) do
		attributes[attributeName] = Attribute.new({
			baseValue = config.baseValue,
			minValue = AttributesConfig.MIN_ATTRIBUTE_VALUE,
			maxValue = AttributesConfig.MAX_ATTRIBUTE_VALUE,
			name = attributeName,
			description = config.description,
		})
	end

	-- Initialize available attribute points (can be adjusted based on level later)
	attributes.availableAttributePoints = AttributesConfig.DefaultAttributePoints
	return attributes :: PlayerAttributes
end

-- Validate attribute value is within bounds
function AttributesConfig.validateAttributeValue(value: number): number
	return math.clamp(value, AttributesConfig.MIN_ATTRIBUTE_VALUE, AttributesConfig.MAX_ATTRIBUTE_VALUE)
end

return AttributesConfig
