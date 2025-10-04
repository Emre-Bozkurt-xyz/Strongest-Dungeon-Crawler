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

local StatsManager = require(game.ServerScriptService.Server.StatsManager)
local function addOrUpdateScalingModifier(player: Player, statName: StatTypes.StatType, modifierId: string, value: number, description: string)
	
	if StatsManager.hasModifier(player, statName, modifierId) then
		StatsManager.updateModifier(player, statName, modifierId, value)
	else
		StatsManager.addModifier(
			player,
			statName,
			StatModifier.new({
				source_id = modifierId,
				type = "flat",
				value = value,
				description = description,
			})
		)
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
	}
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
