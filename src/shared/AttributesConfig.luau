--!strict
-- Shared configuration for player attributes system
-- This file defines all available attributes and their properties

local Attribute = require(game.ReplicatedStorage.Shared.AttributeClass)
local AttributeTypes = require(game.ReplicatedStorage.Shared.AttributeTypes)
local StatTypes = require(game.ReplicatedStorage.Shared.StatTypes)
local StatModifier = require(game.ReplicatedStorage.Shared.Modifiers.StatModifier)

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
			-- Every point of Intelligence gives +5 Mana
			return intelligenceValue * 5
		end,
	},
}

-- ========================================
-- SCALING RELATIONSHIPS
-- ========================================

-- Define how each attribute scales different stats
AttributesConfig.AttributeMilestones = {
	{
		attribute = AttributeTypes.Attributes.Intelligence,
		applyScaling = function(player: Player, StatsManager: any, intelligenceValue: number)
			local newValue = AttributesConfig.ScalingFormulas.Intelligence.MagicDamageFromValue(intelligenceValue)
			if StatsManager.hasModifier(player, StatTypes.StaticStats.MagicDamage, "IntelligenceScaling") then
				StatsManager.updateModifier(player, StatTypes.StaticStats.MagicDamage, "IntelligenceScaling", newValue)
			else
				StatsManager.addModifier(
					player,
					StatTypes.StaticStats.MagicDamage,
					StatModifier.new({
						source_id = "IntelligenceScaling",
						type = "flat",
						value = newValue,
						description = "Increased Magic Damage from Intelligence",
					})
				)
			end
		end,
	},
	{
		attribute = AttributeTypes.Attributes.Intelligence,
		applyScaling = function(player: Player, StatsManager: any, intelligenceValue: number)
			local newValue = AttributesConfig.ScalingFormulas.Intelligence.ManaFromValue(intelligenceValue)
			if StatsManager.hasModifier(player, StatTypes.PoolStats.Mana, "IntelligenceScaling") then
				StatsManager.updateModifier(player, StatTypes.PoolStats.Mana, "IntelligenceScaling", newValue)
			else
				StatsManager.addModifier(
					player,
					StatTypes.PoolStats.Mana,
					StatModifier.new({
						source_id = "IntelligenceScaling",
						type = "flat",
						value = newValue,
						description = "Increased Mana from Intelligence",
					})
				)
			end
		end,
	},
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

	return attributes :: PlayerAttributes
end

-- Validate attribute value is within bounds
function AttributesConfig.validateAttributeValue(value: number): number
	return math.clamp(value, AttributesConfig.MIN_ATTRIBUTE_VALUE, AttributesConfig.MAX_ATTRIBUTE_VALUE)
end

return AttributesConfig
