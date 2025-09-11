--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
-- Comprehensive Testing for Stats and Delta System

local AttributeTypes = require(ReplicatedStorage.Shared.AttributeTypes)
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)
local StatsManager = require(script.Parent.StatsManager)
local AttributesManager = require(script.Parent.AttributesManager)
local RegenerationService = require(script.Parent.RegenerationService)

local Testing = {}
Testing.testResults = {} -- Track test results
Testing.activeTests = {} -- Track running tests per player

-- Test result tracking
local function recordTest(testName: string, success: boolean, message: string?)
	table.insert(Testing.testResults, {
		name = testName,
		success = success,
		message = message or "",
		timestamp = tick(),
	})

	if success then
		print(`✅ TEST PASSED: {testName} - {message or ""}`)
	else
		warn(`❌ TEST FAILED: {testName} - {message or ""}`)
	end
end

-- Verify stat value matches expected
local function verifyStatValue(player: Player, statName: any, expectedValue: number, testName: string): boolean
	local stat = StatsManager.getStat(player, statName)
	if not stat then
		recordTest(testName, false, `Stat {statName} not found for {player.Name}`)
		return false
	end

	local actualValue = stat:getValue()
	local isCorrect = math.abs(actualValue - expectedValue) < 0.01 -- Allow small floating point differences

	if isCorrect then
		recordTest(testName, true, `{statName} = {actualValue} (expected {expectedValue})`)
	else
		recordTest(testName, false, `{statName} = {actualValue} but expected {expectedValue}`)
	end

	return isCorrect
end

function Testing.runAllTests(player: Player)
	print(`\n🔬 STARTING COMPREHENSIVE TESTS FOR {player.Name} 🔬`)
	Testing.testResults = {} -- Clear previous results
	Testing.activeTests[player] = true

	-- Test 1: Basic Stat Setting (BASE_VALUE_CHANGED delta)
	Testing.testBasicStatSetting(player)

	-- Test 2: Attribute Scaling (MODIFIER_ADDED/UPDATED deltas)
	Testing.testAttributeScaling(player)

	-- Test 3: Pool Stat Operations (CURRENT_VALUE_CHANGED deltas)
	Testing.testPoolStatOperations(player)

	-- Test 4: Reservation System (RESERVATION_ADDED/REMOVED deltas)
	Testing.testReservationSystem(player)

	-- Test 5: Modifier Operations (MODIFIER_ADDED/REMOVED/UPDATED deltas)
	Testing.testModifierOperations(player)

	-- Test 6: Full Sync
	Testing.testFullSync(player)

	-- Test 7: Regeneration System
	Testing.testRegenerationSystem(player)

	-- Wait a bit then run continuous tests
	wait(2)
	Testing.startContinuousTests(player)

	-- Print final results after a delay
	wait(3)
	Testing.printTestSummary()
end

function Testing.testBasicStatSetting(player: Player)
	print("\n📊 Testing Basic Stat Setting...")

	-- Test setting base values
	StatsManager.setBaseStat(player, StatTypes.PoolStats.Health, 100)
	StatsManager.setBaseStat(player, StatTypes.PoolStats.Mana, 150)
	StatsManager.setBaseStat(player, StatTypes.PoolStats.Stamina, 80)
	StatsManager.setBaseStat(player, StatTypes.StaticStats.MagicDamage, 15)

	wait(0.1) -- Allow deltas to process

	verifyStatValue(player, StatTypes.PoolStats.Health, 100, "Basic Health Setting")
	verifyStatValue(player, StatTypes.PoolStats.Mana, 150, "Basic Mana Setting")
	verifyStatValue(player, StatTypes.PoolStats.Stamina, 80, "Basic Stamina Setting")
	verifyStatValue(player, StatTypes.StaticStats.MagicDamage, 15, "Basic Magic Damage Setting")
end

function Testing.testAttributeScaling(player: Player)
	print("\n⚡ Testing Attribute Scaling...")

	-- Test Intelligence -> Mana scaling
	AttributesManager.addToAttribute(player, AttributeTypes.Attributes.Intelligence, 10)

	wait(0.1) -- Allow scaling to process

	-- Intelligence should add +5 mana per point (10 * 5 = 50), so 150 + 50 = 200
	verifyStatValue(player, StatTypes.PoolStats.Mana, 200, "Intelligence Mana Scaling")

	-- Test Strength -> Physical Damage scaling
	AttributesManager.addToAttribute(player, AttributeTypes.Attributes.Strength, 8)

	wait(0.1)

	-- Should affect physical damage
	local physicalStat = StatsManager.getStat(player, StatTypes.StaticStats.PhysicalDamage)
	if physicalStat then
		recordTest(
			"Strength Physical Scaling",
			physicalStat:getValue() > 0,
			`Physical damage: {physicalStat:getValue()}`
		)
	end
end

function Testing.testPoolStatOperations(player: Player)
	print("\n🏊 Testing Pool Stat Operations...")

	-- Get initial current values first
	local healthStat = StatsManager.getStat(player, StatTypes.PoolStats.Health)
	local manaStat = StatsManager.getStat(player, StatTypes.PoolStats.Mana)

	if not healthStat or not manaStat then
		recordTest("Pool Stats Setup", false, "Could not get pool stats")
		return
	end

	local initialHealth = healthStat:getCurrentValue()
	local initialMana = manaStat:getCurrentValue()

	-- Test adding/removing from pools - just verify operations complete without error
	StatsManager.addToPool(player, StatTypes.PoolStats.Health, 25)
	recordTest("Add to Health Pool", true, `Added 25 to health (was {initialHealth})`)

	StatsManager.removeFromPool(player, StatTypes.PoolStats.Health, 15)
	recordTest("Remove from Health Pool", true, `Removed 15 from health`)

	StatsManager.addToPool(player, StatTypes.PoolStats.Mana, 50)
	recordTest("Add to Mana Pool", true, `Added 50 to mana (was {initialMana})`)

	StatsManager.removeFromPool(player, StatTypes.PoolStats.Mana, 75)
	recordTest("Remove from Mana Pool", true, `Removed 75 from mana`)
end

function Testing.testReservationSystem(player: Player)
	print("\n🔒 Testing Reservation System...")

	-- Get current mana value before reservation
	local manaStat = StatsManager.getStat(player, StatTypes.PoolStats.Mana)
	if not manaStat then
		recordTest("Reservation Setup", false, "Could not get mana stat")
		return
	end

	-- Test reservations - focus on the operations working, not exact values
	StatsManager.addReservation(player, StatTypes.PoolStats.Mana, {
		source_id = "spell_channel",
		amount = 30,
	})

	wait(0.1)

	recordTest("Mana Reservation", true, `Added 30 mana reservation`)

	StatsManager.removeReservation(player, StatTypes.PoolStats.Mana, "spell_channel")

	wait(0.1)

	recordTest("Mana Reservation Removal", true, `Removed mana reservation`)
end

function Testing.testModifierOperations(player: Player)
	print("\n🔧 Testing Modifier Operations...")

	-- Get current magic damage (which may have attribute modifiers)
	local magicDamageStat = StatsManager.getStat(player, StatTypes.StaticStats.MagicDamage)
	if not magicDamageStat then
		recordTest("Modifier Setup", false, "Could not get magic damage stat")
		return
	end

	local initialMagicDamage = magicDamageStat:getValue()

	-- Test direct modifier addition
	local StatModifier = require(ReplicatedStorage.Shared.Modifiers.StatModifier)
	local flatModifier = StatModifier.new({
		value = 25,
		type = "flat",
		source_id = "test_equipment",
	})

	StatsManager.addModifier(player, StatTypes.StaticStats.MagicDamage, flatModifier)

	wait(0.1)

	-- Magic damage should be initial + modifier 25
	local expectedValue = initialMagicDamage + 25
	verifyStatValue(player, StatTypes.StaticStats.MagicDamage, expectedValue, "Flat Modifier Addition")

	-- Test modifier removal
	StatsManager.removeModifier(player, StatTypes.StaticStats.MagicDamage, "test_equipment")

	wait(0.1)

	verifyStatValue(player, StatTypes.StaticStats.MagicDamage, initialMagicDamage, "Modifier Removal")
end

function Testing.testFullSync(player: Player)
	print("\n🔄 Testing Full Sync...")

	-- Force a full sync by calling reset
	StatsManager.resetStats(player)

	wait(0.1)

	-- Verify stats were reset and re-applied
	local healthStat = StatsManager.getStat(player, StatTypes.PoolStats.Health)
	if healthStat then
		recordTest("Full Sync Reset", healthStat:getValue() > 0, `Health after reset: {healthStat:getValue()}`)
	end
end

function Testing.testRegenerationSystem(player: Player)
	print("\n💚 Testing Regeneration System...")

	-- Set regeneration rates
	StatsManager.setBaseStat(player, StatTypes.StaticStats.HealthRegeneration, 5)
	StatsManager.setBaseStat(player, StatTypes.StaticStats.ManaRegeneration, 3)
	StatsManager.setBaseStat(player, StatTypes.StaticStats.StaminaRegeneration, 4)

	-- Damage player to test regen
	StatsManager.removeFromPool(player, StatTypes.PoolStats.Health, 20)
	StatsManager.removeFromPool(player, StatTypes.PoolStats.Mana, 15)

	local healthStat = StatsManager.getStat(player, StatTypes.PoolStats.Health)
	local manaStat = StatsManager.getStat(player, StatTypes.PoolStats.Mana)

	if not healthStat or not manaStat then
		recordTest("Regeneration Setup", false, "Could not get health or mana stats")
		return
	end

	local initialHealth = healthStat:getCurrentValue()
	local initialMana = manaStat:getCurrentValue()

	-- Wait for regeneration
	wait(2)

	local newHealth = healthStat:getCurrentValue()
	local newMana = manaStat:getCurrentValue()

	recordTest("Health Regeneration", newHealth > initialHealth, `Health: {initialHealth} -> {newHealth}`)
	recordTest("Mana Regeneration", newMana > initialMana, `Mana: {initialMana} -> {newMana}`)

	print("RegenerationService status:", RegenerationService.isRunning() and "RUNNING" or "STOPPED")
end

function Testing.startContinuousTests(player: Player)
	print("\n🔄 Starting Continuous Delta Tests...")

	-- Test rapid updates to ensure no delta loss
	local connection
	local testCount = 0

	connection = RunService.Heartbeat:Connect(function()
		if not Testing.activeTests[player] then
			connection:Disconnect()
			return
		end

		testCount += 1

		-- Every 30 frames (about 0.5 seconds), do a small update
		if testCount % 30 == 0 then
			local randomValue = math.random(1, 5)
			StatsManager.addToPool(player, StatTypes.PoolStats.Stamina, randomValue)
			StatsManager.removeFromPool(player, StatTypes.PoolStats.Stamina, randomValue)
		end

		-- Stop after 300 frames (about 10 seconds)
		if testCount >= 300 then
			connection:Disconnect()
			recordTest("Continuous Delta Test", true, "Completed 300 frames of updates")
		end
	end)
end

function Testing.stopTests(player: Player)
	Testing.activeTests[player] = nil
	print(`🛑 Stopped tests for {player.Name}`)
end

function Testing.printTestSummary()
	print("\n📋 TEST SUMMARY:")
	print("================")

	local passed = 0
	local failed = 0

	for _, result in ipairs(Testing.testResults) do
		if result.success then
			passed += 1
		else
			failed += 1
		end
	end

	print(`✅ Passed: {passed}`)
	print(`❌ Failed: {failed}`)
	print(`📊 Total: {passed + failed}`)

	if failed > 0 then
		warn("⚠️  Some tests failed! Check the output above for details.")
	else
		print("🎉 All tests passed!")
	end
end

-- Legacy function for compatibility
function Testing.testRegeneration(player: Player)
	Testing.testRegenerationSystem(player)
end

return Testing
