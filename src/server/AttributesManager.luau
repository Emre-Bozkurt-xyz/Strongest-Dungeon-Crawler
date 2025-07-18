--!strict
-- Server-side player attributes management system
-- Handles all attribute modifications and syncing to clients

local Players = game:GetService("Players")

local StatsManager = require(script.Parent.StatsManager)
local AttributesConfig = require(game.ReplicatedStorage.Shared.AttributesConfig)
local AttributeTypes = require(game.ReplicatedStorage.Shared.AttributeTypes)
local NetworkManager = require(script.Parent.NetworkManager)

-- Import types from central location
type PlayerAttributes = AttributeTypes.PlayerAttributes
type AttributeType = AttributeTypes.AttributeType
type AttributeModifier = AttributeTypes.AttributeModifier

local AttributesManager = {}
local playerAttributes: { [Player]: PlayerAttributes } = {}

-- Serialize attributes for network transmission
function AttributesManager.serializeAttributes(attributes: PlayerAttributes)
	local serialized = {} :: any

	-- Include available attribute points
	serialized.availableAP = attributes.availableAttributePoints

	-- Process each attribute (excluding availableAttributePoints)
	for attributeName, attribute in pairs(attributes) do
		if attributeName ~= "availableAttributePoints" then
			local totalModifierValue = 0
			local modifiers = attribute:getModifierBreakdown()

			-- Calculate total bonus from all modifiers
			for _, modifier in pairs(modifiers) do
				totalModifierValue += modifier.value
			end

			serialized[attributeName] = {
				base = attribute:getBaseValue(),
				bonus = totalModifierValue,
				current = attribute:getValue(), -- Total (base + bonus)
			}
		end
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

	-- Send targeted delta update
	NetworkManager.sendDelta(
		player,
		NetworkManager.createDelta("attributes", "modifier_added", attributeType, {
			modifier = modifier,
			newTotal = attribute:getValue(),
			modifierTotal = attribute:getModifierTotal(),
		})
	)

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
		-- Send targeted delta update
		NetworkManager.sendDelta(
			player,
			NetworkManager.createDelta("attributes", "modifier_removed", attributeType, {
				source_id = source_id,
				newTotal = attribute:getValue(),
				modifierTotal = attribute:getModifierTotal(),
			})
		)
		print(`Removed modifier '{source_id}' from {player.Name}'s {attributeType}`)
	end

	return removed
end

-- Initialize attributes for a new player
local function initializePlayerAttributes(player: Player)
	playerAttributes[player] = AttributesConfig.createDefaultAttributes()

	-- Send initial full sync to player
	NetworkManager.sendFullSync(player, "attributes", playerAttributes[player])

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

	-- Reapply all scaling since attribute values changed
	AttributesManager.applyAllScaling(player)

	-- Send targeted delta update
	NetworkManager.sendDelta(
		player,
		NetworkManager.createDelta("attributes", "attribute_set", attributeType, {
			newBase = validatedValue,
			newTotal = attribute:getValue(),
			modifierTotal = attribute:getModifierTotal(),
		})
	)

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

	-- Reapply all scaling since attribute values changed
	AttributesManager.applyAllScaling(player)

	-- Send targeted delta update
	NetworkManager.sendDelta(
		player,
		NetworkManager.createDelta("attributes", "attribute_added", attributeType, {
			amount = amount,
			newBase = attribute:getBaseValue(),
			newTotal = attribute:getValue(),
			modifierTotal = attribute:getModifierTotal(),
		})
	)

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

	-- Send full sync since all attributes changed
	NetworkManager.sendFullSync(player, "attributes", playerAttributes[player])

	print(`Reset attributes for player: {player.Name}`)
	return true
end

-- Apply all attribute scaling effects to a player's attributes
function AttributesManager.applyAllScaling(player: Player)
	if not playerAttributes[player] then
		warn(`Cannot apply scaling for player {player.Name} - missing attributes`)
		return
	end

	-- Enable batching to prevent individual client updates
	StatsManager.enableBatching(player)

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

	-- Disable batching and send final update
	StatsManager.disableBatching(player)

	print(`Applied attribute scaling for {player.Name}`)
end

-- Connect player events
Players.PlayerAdded:Connect(initializePlayerAttributes)
Players.PlayerRemoving:Connect(cleanupPlayerAttributes)

-- Listen for attributes data requests from clients
local warp = require(game.ReplicatedStorage.Packages.warp)
local attributesRequestSignal = warp.Signal("attributesRequest")
attributesRequestSignal:Connect(function(player: Player)
	if not playerAttributes[player] then
		warn(`Attributes request for {player.Name} but no attributes initialized`)
		return
	end

	-- Send full sync of current attributes
	NetworkManager.sendFullSync(player, "attributes", playerAttributes[player])
	print(`📤 AttributesManager: Sent full sync to {player.Name}`)
end)

print("AttributesManager initialized")

-- Get available attribute points for a player
function AttributesManager.getAvailableAttributePoints(player: Player): number
	if not playerAttributes[player] then
		warn(`Attempted to get available points for player {player.Name} who has no attributes initialized`)
		return 0
	end

	return playerAttributes[player].availableAttributePoints
end

-- Set available attribute points for a player
function AttributesManager.setAvailableAttributePoints(player: Player, points: number)
	if not playerAttributes[player] then
		warn(`Attempted to set available points for player {player.Name} who has no attributes initialized`)
		return false
	end

	playerAttributes[player].availableAttributePoints = math.max(0, points)

	-- Send updated attributes to client
	NetworkManager.sendFullSync(player, "attributes", playerAttributes[player])

	print(`Set {player.Name}'s available attribute points to {points}`)
	return true
end

-- Add available attribute points (e.g., from leveling up)
function AttributesManager.addAvailableAttributePoints(player: Player, points: number)
	if not playerAttributes[player] then
		warn(`Attempted to add available points for player {player.Name} who has no attributes initialized`)
		return false
	end

	local currentPoints = playerAttributes[player].availableAttributePoints
	local newPoints = currentPoints + points

	return AttributesManager.setAvailableAttributePoints(player, newPoints)
end

-- Spend attribute points to increase an attribute
function AttributesManager.spendAttributePoint(player: Player, attributeType: AttributeType): boolean
	if not playerAttributes[player] then
		warn(`Attempted to spend attribute point for player {player.Name} who has no attributes initialized`)
		return false
	end

	local availablePoints = playerAttributes[player].availableAttributePoints
	if availablePoints <= 0 then
		warn(`Player {player.Name} has no available attribute points to spend`)
		return false
	end

	local attribute = (playerAttributes[player] :: any)[attributeType]
	if not attribute then
		warn(`Attribute {attributeType} not found for player {player.Name}`)
		return false
	end

	-- Increase the base value of the attribute
	local currentBase = attribute:getBaseValue()
	local newBase = currentBase + 1

	-- Validate the new value is within bounds
	local validatedValue = AttributesConfig.validateAttributeValue(newBase)
	if validatedValue ~= newBase then
		warn(`Cannot increase {attributeType} for {player.Name} - would exceed maximum value`)
		return false
	end

	-- Apply the changes
	attribute:setBaseValue(newBase)
	playerAttributes[player].availableAttributePoints = availablePoints - 1

	-- Reapply all scaling since attribute values changed
	AttributesManager.applyAllScaling(player)

	-- Send targeted delta update
	NetworkManager.sendDelta(
		player,
		NetworkManager.createDelta("attributes", "attribute_increased", attributeType, {
			newBase = newBase,
			newTotal = attribute:getValue(),
			modifierTotal = attribute:getModifierTotal(),
			availablePoints = availablePoints - 1,
		})
	)

	print(
		`{player.Name} spent 1 point on {attributeType}. New base: {newBase}, Available points: {availablePoints - 1}`
	)
	return true
end

-- Debug and testing functions
function AttributesManager.debugPlayerAttributes(player: Player)
	if not playerAttributes[player] then
		print(`No attributes found for {player.Name}`)
		return
	end

	print(`=== Attributes Debug for {player.Name} ===`)
	print(`Available Points: {playerAttributes[player].availableAttributePoints}`)

	for attributeName, attribute in pairs(playerAttributes[player]) do
		if attributeName ~= "availableAttributePoints" then
			print(`{attributeName}: base={attribute:getBaseValue()}, current={attribute:getValue()}`)
		end
	end
	print(`=============================`)
end

-- Test function to add some attribute points for testing
function AttributesManager.giveTestAttributePoints(player: Player, points: number)
	return AttributesManager.addAvailableAttributePoints(player, points or 10)
end

-- Attributes System Handler for NetworkManager
local attributesHandler = {
	serialize = function(data: PlayerAttributes): any
		return AttributesManager.serializeAttributes(data)
	end,
	deserialize = function(data: any): PlayerAttributes
		-- For now, return the data as-is since we don't have client-side deserialization yet
		return data
	end,
	applyDelta = function(_currentData, delta)
		-- Handle client requests to modify attributes
		if delta.type == "increase_attribute" then
			local player = Players:GetPlayerByUserId(delta.data.playerId)
			if not player then
				warn("AttributesManager: Player not found for increase_attribute delta")
				return false, _currentData
			end

			local attributeType = delta.target :: string

			-- Use the existing spendAttributePoint function which handles all the logic
			local success = AttributesManager.spendAttributePoint(player, attributeType :: any)
			return success, playerAttributes[player]
		end

		-- For other types, return true (no-op for now)
		return true, _currentData
	end,
}

-- Register attributes system with NetworkManager
NetworkManager.registerSystem("attributes", attributesHandler)

return AttributesManager
