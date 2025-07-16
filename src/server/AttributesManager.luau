--!strict
-- Server-side player attributes management system
-- Handles all attribute modifications and syncing to clients

local Players = game:GetService("Players")

local Warp = require(game.ReplicatedStorage.Packages.warp)
local AttributesConfig = require(game.ReplicatedStorage.Shared.AttributesConfig)

type AttributeType = AttributesConfig.AttributeType
type AttributeData = AttributesConfig.AttributeData
type PlayerAttributes = AttributesConfig.PlayerAttributes
type AttributeModifier = AttributesConfig.AttributeModifier

local AttributesManager = {}
local playerAttributes: { [Player]: PlayerAttributes } = {}

-- Warp events for networking
local attributesUpdateEvent = Warp.Server("AttributesUpdate")
local attributesRequestEvent = Warp.Server("AttributesRequest")

-- TESTING
local healthChangedEvent = Warp.Server("HealthChanged")
local staminaChangedEvent = Warp.Server("StaminaChanged")
local manaChangedEvent = Warp.Server("ManaChanged")

-- Initialize attributes for a new player
local function initializePlayerAttributes(player: Player)
	playerAttributes[player] = AttributesConfig.createDefaultAttributes()

	-- Send initial attributes to the player
	attributesUpdateEvent:Fire(true, player, playerAttributes[player])

	print(`Initialized attributes for player: {player.Name}`)

	-- TESTING: Send initial health, stamina, and mana
	task.spawn(function()
		while true do
			local healthMax = math.random(50, 200)
			healthChangedEvent:Fire(true, player, math.random(10, healthMax), healthMax)

			local manaMax = math.random(100, 250)
			manaChangedEvent:Fire(true, player, math.random(10, manaMax), manaMax)

			staminaChangedEvent:Fire(true, player, math.random(10, 100), 100)
			task.wait(3)
		end
	end)
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
	local attribute = playerAttributes[player][attributeType]

	-- Recalculate current value
	attribute.base = validatedValue

	-- Notify the client of the change
	attributesUpdateEvent:Fire(true, player, playerAttributes[player])

	print(
		`Updated {player.Name}'s {attributeType} to {attribute.base + AttributesConfig.getAdditiveModifiers(attribute)} (base: {attribute.base}, modifiers: {AttributesConfig.getAdditiveModifiers(
			attribute
		)})`
	)
	return true
end

-- Add to a player's attribute (useful for leveling up)
function AttributesManager.addToAttribute(player: Player, attributeType: AttributeType, amount: number)
	if not playerAttributes[player] then
		warn(`Attempted to add to attribute for player {player.Name} who has no attributes initialized`)
		return false
	end

	local attribute = playerAttributes[player][attributeType]
	local currentValue = attribute.base
	local newValue = currentValue + amount

	return AttributesManager.setAttribute(player, attributeType, newValue)
end

-- Get a player's current attribute value
function AttributesManager.getAttribute(player: Player, attributeType: AttributeType): AttributeData?
	if not playerAttributes[player] then
		return nil
	end

	return playerAttributes[player][attributeType]
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
	attributesUpdateEvent:Fire(true, player, playerAttributes[player])

	print(`Reset attributes for player: {player.Name}`)
	return true
end

-- Handle client requests for attributes
local function handleAttributesRequest(player: Player)
	if playerAttributes[player] then
		attributesUpdateEvent:Fire(true, player, playerAttributes[player])
	else
		initializePlayerAttributes(player)
	end
end

-- Connect events
attributesRequestEvent:Connect(handleAttributesRequest)

-- Connect player events
Players.PlayerAdded:Connect(initializePlayerAttributes)
Players.PlayerRemoving:Connect(cleanupPlayerAttributes)

return AttributesManager
