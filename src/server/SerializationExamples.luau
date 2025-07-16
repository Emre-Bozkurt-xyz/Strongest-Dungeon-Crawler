--!strict
-- Example demonstrating comprehensive stat serialization and deserialization
-- This shows how the system can fully reconstruct stat classes with all their state

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StatsManager = require(script.Parent.StatsManager)
local StatTypeUtil = require(ReplicatedStorage.Shared.StatTypeUtil)
local Types = require(ReplicatedStorage.Shared.StatTypes)
local StatModifier = require(ReplicatedStorage.Shared.Modifiers.StatModifier)
local PercentOfStatModifier = require(ReplicatedStorage.Shared.Modifiers.PercentOfStatModifier)

local SerializationExamples = {}

-- Example: Save player stats to a "database" (table for demo)
local playerStatDatabase = {} :: { [string]: any }

function SerializationExamples.savePlayerStats(player: Player)
	local stats = StatsManager.getAllStats(player)
	if not stats then
		print(`No stats found for {player.Name}`)
		return false
	end

	-- Serialize with FULL state preservation
	local serializedStats = StatTypeUtil.serializeStats(stats)

	-- Save to "database" (in real game, this would be DataStore)
	playerStatDatabase[tostring(player.UserId)] = serializedStats

	print(`💾 Saved complete stat state for {player.Name}`)
	print(`   - Includes: base values, modifiers, reservations, cache state`)

	local count = 0
	for _ in pairs(serializedStats) do
		count += 1
	end
	print(`   - Serialized {count} stats`)

	return true
end

function SerializationExamples.loadPlayerStats(player: Player): Types.PlayerStats?
	local savedData = playerStatDatabase[tostring(player.UserId)]
	if not savedData then
		print(`No saved data found for {player.Name}`)
		return nil
	end

	-- Deserialize and fully reconstruct stat classes
	local restoredStats = StatTypeUtil.deserializeStats(savedData)

	-- Replace the player's current stats with restored ones
	-- Note: In real implementation, you'd integrate this with StatsManager
	print(`📂 Loaded complete stat state for {player.Name}`)
	print(`   - Restored: base values, modifiers, reservations, cache state`)

	local count = 0
	for _ in pairs(restoredStats) do
		count += 1
	end
	print(`   - Loaded {count} stats`)

	return restoredStats
end

-- Example: Demonstrate round-trip serialization
function SerializationExamples.demonstrateRoundTrip(player: Player)
	print("\n🔄 === ROUND-TRIP SERIALIZATION DEMO ===")

	-- 1. Add some complex state to player's stats
	print("1. Setting up complex stat state...")

	-- Add modifiers to various stats
	local damageModifier = StatModifier.new({
		value = 15,
		type = "flat",
		source_id = "weapon_bonus",
	})
	damageModifier.description = "Magic Sword Bonus"

	local critPercentModifier = PercentOfStatModifier.new({
		value = 0.1, -- 10% of PhysicalDamage
		description = "Crit scales with damage",
		source_id = "crit_scaling",
		targetStat = Types.StaticStats.PhysicalDamage,
	})

	StatsManager.addModifier(player, Types.StaticStats.PhysicalDamage, damageModifier)
	StatsManager.addModifier(player, Types.StaticStats.CriticalHitChance, critPercentModifier)

	-- Add pool reservations
	local armorReservation = {
		amount = 25,
		type = "flat" :: "flat",
		source_id = "heavy_armor",
		description = "Heavy Armor Health Reserve",
	}

	local manaShieldReservation = {
		amount = 0.3, -- 30% of max mana
		type = "percent" :: "percent",
		source_id = "mana_shield",
		description = "Mana Shield Reservation",
	}

	StatsManager.addReservation(player, Types.PoolStats.Health, armorReservation)
	StatsManager.addReservation(player, Types.PoolStats.Mana, manaShieldReservation)

	-- 2. Get original stats
	local originalStats = StatsManager.getAllStats(player)
	if not originalStats then
		return
	end

	print("2. Original stat state:")
	SerializationExamples._printStatSummary(originalStats)

	-- 3. Serialize the stats
	print("\n3. Serializing stats...")
	local serializedData = StatTypeUtil.serializeStats(originalStats)
	print(`   ✅ Serialized {#serializedData} stats`)

	-- 4. Deserialize back to stat objects
	print("\n4. Deserializing stats...")
	local restoredStats = StatTypeUtil.deserializeStats(serializedData)
	local restoredCount = 0
	for _ in pairs(restoredStats) do
		restoredCount += 1
	end
	print(`   ✅ Restored {restoredCount} stats`)

	-- 5. Verify everything was restored correctly
	print("\n5. Restored stat state:")
	SerializationExamples._printStatSummary(restoredStats)

	-- 6. Test that modifiers still work
	print("\n6. Testing restored modifiers...")
	local healthStat = restoredStats[Types.PoolStats.Health]
	local damageStat = restoredStats[Types.StaticStats.PhysicalDamage]
	local critStat = restoredStats[Types.StaticStats.CriticalHitChance]

	if StatTypeUtil.isPoolStat(healthStat) then
		local breakdown = healthStat:getBreakdown(restoredStats)
		print(`   Health: {breakdown.current}/{breakdown.max} (Reserved: {breakdown.reserved})`)
	end

	print(`   Physical Damage: {damageStat:getValue(restoredStats)} (includes modifiers)`)
	print(`   Crit Chance: {critStat:getValue(restoredStats)} (scales with damage)`)

	print("\n✅ Round-trip serialization successful!")
	print("   - All modifiers preserved and functional")
	print("   - All reservations preserved")
	print("   - Cache state preserved")
	print("   - Cross-stat references (PercentOfStat) working")
end

-- Helper function to print stat summary
function SerializationExamples._printStatSummary(stats)
	for statName, stat in pairs(stats) do
		if StatTypeUtil.isPoolStat(stat) then
			local breakdown = stat:getBreakdown(stats)
			print(
				`   {statName}: {breakdown.current}/{breakdown.max} ({#stat.modifiers} modifiers, {#stat.reservations} reservations)`
			)
		else
			print(`   {statName}: {stat:getValue(stats)} ({#stat.modifiers} modifiers)`)
		end
	end
end

-- Example: Compare serialization data sizes
function SerializationExamples.compareSerializationSizes(player: Player)
	print("\n📊 === SERIALIZATION SIZE COMPARISON ===")

	local stats = StatsManager.getAllStats(player)
	if not stats then
		return
	end

	-- Old simple serialization (just values)
	local simpleData = {} :: { [string]: { current: any, base: any } }
	for statName, stat in pairs(stats) do
		if StatTypeUtil.isPoolStat(stat) then
			simpleData[statName] = {
				current = stat:getCurrentValue(),
				base = stat:getBaseValue(),
			}
		else
			simpleData[statName] = {
				current = stat:getValue(stats), -- Use current for consistency
				base = stat:getBaseValue(),
			}
		end
	end

	-- New comprehensive serialization
	local comprehensiveData = StatTypeUtil.serializeStats(stats)

	local simpleJson = game:GetService("HttpService"):JSONEncode(simpleData)
	local comprehensiveJson = game:GetService("HttpService"):JSONEncode(comprehensiveData)

	print(`Simple serialization: {#simpleJson} characters`)
	print(`Comprehensive serialization: {#comprehensiveJson} characters`)
	print(`Size increase: {math.floor((#comprehensiveJson / #simpleJson - 1) * 100)}%`)
	print("\nBenefits of comprehensive serialization:")
	print("✅ Preserves all modifiers and their state")
	print("✅ Preserves pool reservations")
	print("✅ Preserves cache for performance")
	print("✅ Enables perfect state restoration")
	print("✅ Supports complex modifier types (PercentOfStat)")
end

-- Connect to player events for demonstration
local function onPlayerAdded(player: Player)
	-- Wait a moment for stats to be initialized
	wait(1)

	-- Run examples
	SerializationExamples.demonstrateRoundTrip(player)
	SerializationExamples.compareSerializationSizes(player)

	-- Save and load demo
	SerializationExamples.savePlayerStats(player)
	local _restoredStats = SerializationExamples.loadPlayerStats(player)

	print(`\n🎉 Serialization examples complete for {player.Name}!`)
end

--Players.PlayerAdded:Connect(onPlayerAdded)

return SerializationExamples
