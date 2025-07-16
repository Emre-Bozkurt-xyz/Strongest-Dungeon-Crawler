--!strict
-- Server-side player attributes management system
-- Handles all attribute modifications and syncing to clients

local Players = game:GetService("Players")

local StatsManager = require(script.Parent.StatsManager)
local Warp = require(game.ReplicatedStorage.Packages.warp)
local AttributesConfig = require(game.ReplicatedStorage.Shared.AttributesConfig)
local AttributeTypes = require(game.ReplicatedStorage.Shared.AttributeTypes)

-- Import types from central location
type PlayerAttributes = AttributeTypes.PlayerAttributes
type AttributeType = AttributeTypes.AttributeType
type AttributeModifier = AttributeTypes.AttributeModifier

local AttributesManager = {}
local playerAttributes: { [Player]: PlayerAttributes } = {}

-- Warp events for networking
local attributesUpdateEvent = Warp.Server("AttributesUpdate")
local attributesRequestEvent = Warp.Server("AttributesRequest")

local attributesChangedSignal = Warp.Signal("AttributesChanged")

-- Serialize attributes for network transmission
function AttributesManager.serializeAttributes(attributes: PlayerAttributes)
	local serialized = {} :: any

	for attributeName, attribute in pairs(attributes) do
		serialized[attributeName] = {
			base = attribute:getBaseValue(),
			current = attribute:getValue(),
			modifiers = attribute:getModifierBreakdown(),
		}
	end

	return serialized
end

-- Add a modifier to a player's attribute
function AttributesManager.addModifier(player: Player, attributeType: AttributeType, modifier: AttributeModifier)
	if not playerAttributes[player] then
		warn(`Attempted to add modifier for player {player.Name} who has no attributes initialized`)
		return false
	end

	local attribute = (playerAttributes[player] :: any)[attributeType]
	if not attribute then
		warn(`Attribute {attributeType} not found for player {player.Name}`)
		return false
	end

	attribute:addModifier(modifier)

	-- Notify the client of the change
	attributesChangedSignal:Fire(player, playerAttributes[player])

	print(`Added modifier '{modifier.source_id}' to {player.Name}'s {attributeType}`)
	return true
end

-- Remove a modifier from a player's attribute
function AttributesManager.removeModifier(player: Player, attributeType: AttributeType, source_id: string)
	if not playerAttributes[player] then
		warn(`Attempted to remove modifier for player {player.Name} who has no attributes initialized`)
		return false
	end

	local attribute = (playerAttributes[player] :: any)[attributeType]
	if not attribute then
		warn(`Attribute {attributeType} not found for player {player.Name}`)
		return false
	end

	local removed = attribute:removeModifier(source_id)

	if removed then
		-- Notify the client of the change
		attributesChangedSignal:Fire(player, playerAttributes[player])
		print(`Removed modifier '{source_id}' from {player.Name}'s {attributeType}`)
	end

	return removed
end

-- Initialize attributes for a new player
local function initializePlayerAttributes(player: Player)
	playerAttributes[player] = AttributesConfig.createDefaultAttributes()

	-- Send initial attributes to the player (serialize for network)
	attributesChangedSignal:Fire(player, playerAttributes[player])

	print(`Initialized attributes for player: {player.Name}`)
end

-- Clean up when player leaves
local function cleanupPlayerAttributes(player: Player)
	playerAttributes[player] = nil
	print(`Cleaned up attributes for player: {player.Name}`)
end

-- Update a player's attribute and notify client
function AttributesManager.setAttribute(player: Player, attributeType: AttributeType, newValue: number)
	if not playerAttributes[player] then
		warn(`Attempted to set attribute for player {player.Name} who has no attributes initialized`)
		return false
	end

	local validatedValue = AttributesConfig.validateAttributeValue(newValue)
	local attribute = (playerAttributes[player] :: any)[attributeType]

	if not attribute then
		warn(`Attribute {attributeType} not found for player {player.Name}`)
		return false
	end

	-- Set the base value using the class method
	attribute:setBaseValue(validatedValue)

	-- Notify the client of the change
	attributesChangedSignal:Fire(player, playerAttributes[player])

	print(
		`Updated {player.Name}'s {attributeType} to {attribute:getValue()} (base: {attribute:getBaseValue()}, modifiers: {attribute:getModifierTotal()})`
	)
	return true
end

-- Add to a player's attribute (useful for leveling up)
function AttributesManager.addToAttribute(player: Player, attributeType: AttributeType, amount: number)
	if not playerAttributes[player] then
		warn(`Attempted to add to attribute for player {player.Name} who has no attributes initialized`)
		return false
	end

	local attribute = (playerAttributes[player] :: any)[attributeType]
	if not attribute then
		warn(`Attribute {attributeType} not found for player {player.Name}`)
		return false
	end

	-- Use the class method to add to base value
	attribute:addToBaseValue(amount)

	-- Notify the client of the change
	attributesChangedSignal:Fire(player, playerAttributes[player])

	print(`Added {amount} to {player.Name}'s {attributeType}. New value: {attribute:getValue()}`)
	return true
end

-- Get a player's attribute object
function AttributesManager.getAttribute(player: Player, attributeType: AttributeType)
	if not playerAttributes[player] then
		return nil
	end

	return (playerAttributes[player] :: any)[attributeType]
end

-- Get a player's current attribute value
function AttributesManager.getAttributeValue(player: Player, attributeType: AttributeType): number?
	if not playerAttributes[player] then
		return nil
	end

	local attribute = (playerAttributes[player] :: any)[attributeType]
	return attribute and attribute:getValue() or nil
end

-- Get all attributes for a player
function AttributesManager.getAllAttributes(player: Player): PlayerAttributes?
	return playerAttributes[player]
end

-- Reset all attributes to default values
function AttributesManager.resetAttributes(player: Player)
	if not playerAttributes[player] then
		warn(`Attempted to reset attributes for player {player.Name} who has no attributes initialized`)
		return false
	end

	playerAttributes[player] = AttributesConfig.createDefaultAttributes()
	attributesChangedSignal:Fire(player, playerAttributes[player])

	print(`Reset attributes for player: {player.Name}`)
	return true
end

-- Apply all attribute scaling effects to a player's attributes
function AttributesManager.applyAllScaling(player: Player)
	if not playerAttributes[player] then
		warn(`Cannot apply scaling for player {player.Name} - missing attributes`)
		return
	end

	for _, attributeMilestone in pairs(AttributesConfig.AttributeMilestones) do
		local attribute = AttributesManager.getAttribute(player, attributeMilestone.attribute)
		if not attribute then
			warn(`Attribute {attributeMilestone.attribute} not found for player {player.Name}`)
			continue
		end

		local intelligenceValue = attribute:getValue()

		-- Apply the scaling formula defined in the milestone
		attributeMilestone.applyScaling(player, StatsManager, intelligenceValue)
	end

	print(`Applied attribute scaling for {player.Name}`)
end

-- Handle client requests for attributes
local function handleAttributesRequest(player: Player)
	if playerAttributes[player] then
		attributesChangedSignal:Fire(player, playerAttributes[player])
	else
		initializePlayerAttributes(player)
	end
end

-- Handle attribute changes
local function handleAttributesChanged(player: Player, attributes: PlayerAttributes)
	if not playerAttributes[player] then
		warn(`Attempted to handle attribute change for player {player.Name} who has no attributes initialized`)
		return
	end

	-- Apply all scaling effects
	AttributesManager.applyAllScaling(player)

	-- Notify the client of the updated attributes
	attributesUpdateEvent:Fire(true, player, AttributesManager.serializeAttributes(attributes))
end

-- Connect events
attributesRequestEvent:Connect(handleAttributesRequest)
attributesChangedSignal:Connect(handleAttributesChanged)

-- Connect player events
Players.PlayerAdded:Connect(initializePlayerAttributes)
Players.PlayerRemoving:Connect(cleanupPlayerAttributes)

print("AttributesManager initialized")

return AttributesManager
