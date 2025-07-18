-- Main server initialization script
print("Server starting...")

-- Initialize the stats management system
local StatsManager = require(script.StatsManager)
local AttributesManager = require(script.AttributesManager)

-- Initialize the regeneration service
local RegenerationService = require(script.RegenerationService)
RegenerationService.start()

-- Debug Controls (set to false to reduce console spam)
local function _setNetworkDebug(enabled: boolean)
	local NetworkManager = require(script.NetworkManager)
	NetworkManager.setDebug(enabled)
	print(`🐛 Network debug mode: {enabled and "ON" or "OFF"}`)
end

-- Example: Uncomment to disable network debug logging
-- setNetworkDebug(false)

-- Example: Set up some demo commands (you can remove these later)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AttributeTypes = require(ReplicatedStorage.Shared.AttributeTypes)
local PercentOfStatModifier = require(ReplicatedStorage.Shared.Modifiers.PercentOfStatModifier)
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)
local Testing = require(script.Testing)

-- Example function to test the system
local function setupPlayerCommands(player: Player)
	-- Wait a bit for the player to load
	wait(10)

	print("Starting in 5s...")

	wait(5)

	-- Apply attribute scaling after stats and attributes are initialized
	AttributesManager.applyAllScaling(player)

	--Testing.runAllTests(player)
	-- small scale testing

	print(`🧪 Server: Testing attribute operations for {player.Name}`)

	StatsManager.addModifier(
		player,
		StatTypes.StaticStats.ManaRegeneration,
		PercentOfStatModifier.new({
			value = 0.1, -- 10% of max mana
			source_id = "mana_regen_test",
			targetStat = StatTypes.PoolStats.Mana,
			description = "Base mana regeneration",
		})
	)

	-- Test adding intelligence
	AttributesManager.addToAttribute(player, AttributeTypes.Attributes.Intelligence, 5)
	print(`Added 5 Intelligence to {player.Name}`)

	-- Debug available points
	local availablePoints = AttributesManager.getAvailableAttributePoints(player)
	print(`{player.Name} has {availablePoints} available attribute points`)

	StatsManager.removeFromPool(player, StatTypes.PoolStats.Mana, 30)
	StatsManager.removeFromPool(player, StatTypes.PoolStats.Health, 30)
	StatsManager.removeFromPool(player, StatTypes.PoolStats.Stamina, 30)

	wait(2)

	-- Test spending an attribute point
	AttributesManager.spendAttributePoint(player, AttributeTypes.Attributes.Intelligence)
	print(`{player.Name} spent 1 attribute point on Intelligence`)

	wait(2)

	-- Add intelligence modifier
	AttributesManager.addModifier(player, AttributeTypes.Attributes.Intelligence, {
		value = 3, -- +3 Intelligence
		source_id = "intelligence_modifier_test",
		description = "Test Intelligence Modifier",
	})
end

-- Connect to new players for demo purposes
Players.PlayerAdded:Connect(function(player)
	spawn(function()
		setupPlayerCommands(player)
	end)
end)

-- Clean up tests when player leaves
Players.PlayerRemoving:Connect(function(player)
	Testing.stopTests(player)
end)

print("Server initialized with Examples")
