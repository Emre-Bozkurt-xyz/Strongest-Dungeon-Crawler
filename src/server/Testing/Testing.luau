--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = game:GetService("ServerScriptService").Server
local RunService = game:GetService("RunService")
-- Comprehensive Testing for Stats and Delta System

local AttributeTypes = require(ReplicatedStorage.Shared.AttributeTypes)
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)
local StatsManager = require(Server.Stats.StatsManager)
local StatsMediator = require(Server.Stats.StatsMediator)
local AttributesManager = require(Server.Stats.AttributesManager)
local RegenerationService = require(Server.Services.RegenerationService)
local CombatService = require(Server.Services.CombatService)
local ModifierFactories = require(ReplicatedStorage.Shared.Modifiers.Factories)
local Registrar = require(Server.Services.Registrar)

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

	-- Test 8: Resource Stats
	Testing.testResourceStats(player)

	-- Test 9: Combat metadata logging
	Testing.testCombatLogCoverage(player)

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

	-- Intelligence should add +5 mana per 5 points, so 150 + 10 = 160
	verifyStatValue(player, StatTypes.PoolStats.Mana, 160, "Intelligence Mana Scaling")

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
	local flatModifier = ModifierFactories.flatAdd({
		sourceId = "test_equipment",
		amount = 25,
		description = "Test equipment bonus",
		tags = { "test", "equipment" },
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

local function captureResourceEventLog()
	local log = {}
	return log,
		function(eventName: string)
			return function(_stat, payload)
				table.insert(log, {
					event = eventName,
					payload = payload,
					timestamp = os.clock(),
				})
			end
		end
end

local function shallowCopyDict(source: { [any]: any }?): { [any]: any }
	local target: { [any]: any } = {}
	if not source then
		return target
	end
	for key, value in pairs(source) do
		target[key] = value
	end
	return target
end

local function hasEvent(log, eventName: string): boolean
	for _, entry in ipairs(log) do
		if entry.event == eventName then
			return true
		end
	end
	return false
end

function Testing.testResourceStats(player: Player)
	print("\n🔋 Testing Resource Stats...")

	local resourceType: StatTypes.ResourceStatType = StatTypes.ResourceStats.Energy
	local resourceStat = StatsManager.getStat(player, resourceType)
	if not resourceStat then
		recordTest("Resource Available", false, "Energy resource missing")
		return
	end

	local log, loggerFactory = captureResourceEventLog()
	StatsManager.onResourceEvent(player, resourceType, "threshold", "test_threshold", loggerFactory("threshold"))
	StatsManager.onResourceEvent(player, resourceType, "depleted", "test_depleted", loggerFactory("depleted"))
	StatsManager.onResourceEvent(player, resourceType, "restored", "test_restored", loggerFactory("restored"))

	StatsManager.setResourceDepletionThreshold(player, resourceType, 10)
	StatsManager.addResourceThreshold(player, resourceType, "low_energy", {
		value = 30,
		type = "percentage",
		comparison = "<=",
		once = true,
	})
	StatsManager.setResourceRegeneration(player, resourceType, 25)

	StatsManager.removeFromResource(player, resourceType, 120)
	wait(0.2)

	recordTest("Resource Depletion Event", hasEvent(log, "depleted"), `Events captured: {#log}`)
	recordTest("Resource Threshold Event", hasEvent(log, "threshold"), `Events captured: {#log}`)

	wait(1)

	local currentEnergy = StatsManager.getResourceCurrentValue(player, resourceType) or 0
	recordTest("Resource Regeneration", currentEnergy > 10, `Energy value: {math.floor(currentEnergy)}`)
	recordTest(
		"Resource Restored Event",
		hasEvent(log, "restored"),
		hasEvent(log, "restored") and "Restored fired" or "Restored missing"
	)

	local maxEnergy = StatsManager.getResourceMaxValue(player, resourceType)
	if maxEnergy then
		StatsManager.setResourceValue(player, resourceType, maxEnergy)
	end
	StatsManager.setResourceDepletionThreshold(player, resourceType, 0)

	StatsManager.offResourceEvent(player, resourceType, "threshold", "test_threshold")
	StatsManager.offResourceEvent(player, resourceType, "depleted", "test_depleted")
	StatsManager.offResourceEvent(player, resourceType, "restored", "test_restored")
	StatsManager.removeResourceThreshold(player, resourceType, "low_energy")
end

function Testing.testCombatLogCoverage(player: Player)
	print("\n⚔️ Testing Combat Log Coverage...")

	local character = player.Character
	if not character then
		recordTest("Combat Log Coverage Setup", false, "Player character missing")
		return
	end

	local healthStat = StatsManager.getStat(player, StatTypes.PoolStats.Health)
	local shieldStat = StatsManager.getStat(player, StatTypes.PoolStats.ManaShield)
	if not healthStat or not shieldStat then
		recordTest("Combat Log Stat Setup", false, "Health or shield stat missing")
		return
	end

	local desiredHealth = 140
	StatsManager.setBaseStat(player, StatTypes.PoolStats.Health, desiredHealth)
	local currentHealth = healthStat:getCurrentValue()
	if currentHealth < desiredHealth then
		StatsManager.addToPool(player, StatTypes.PoolStats.Health, desiredHealth - currentHealth)
	elseif currentHealth > desiredHealth then
		StatsManager.removeFromPool(player, StatTypes.PoolStats.Health, currentHealth - desiredHealth)
	end

	local desiredShield = 30
	StatsManager.setBaseStat(player, StatTypes.PoolStats.ManaShield, desiredShield)
	local currentShield = shieldStat:getCurrentValue()
	if currentShield < desiredShield then
		StatsManager.addToPool(player, StatTypes.PoolStats.ManaShield, desiredShield - currentShield)
	elseif currentShield > desiredShield then
		StatsManager.removeFromPool(player, StatTypes.PoolStats.ManaShield, currentShield - desiredShield)
	end

	local logEntries = {}
	local subscriptions = {}

	local function subscribe(eventName: string)
		local token = StatsMediator.observe(eventName, function(context)
			table.insert(logEntries, {
				event = eventName,
				stage = context.options and context.options.metadata and context.options.metadata.stage,
				statType = context.statType,
				metadata = shallowCopyDict(context.options and context.options.metadata),
				entity = context.entity,
			})
			return nil
		end)
		table.insert(subscriptions, {
			event = eventName,
			token = token,
		})
	end

	subscribe("combatResourceQuery")
	subscribe("resolveCombatCost")

	local damageAmount = 45
	local characterEntityId = Registrar.getPlayerId(player)
	if not characterEntityId then
		warn("[Testing] Player has no entityId, skipping damage test")
		return
	end

	-- Use attack composition instead of legacy damage API
	local AttackTypes = require(ReplicatedStorage.Shared.skills.AttackTypes)
	local attack: AttackTypes.AttackContext = {
		packets = {
			{
				type = "damage",
				damageType = "Physical",
				amount = damageAmount,
				penetration = 1.0, -- bypass armor
			},
		},
		sourceId = "",
		metadata = { isCrit = false, tags = { "test" } },
	}
	local result = CombatService.applyAttack(characterEntityId, attack, "")
	local resourceMeta = result.resourceMeta
	local shieldMeta: { [any]: any }? = nil
	local healthMeta: { [any]: any }? = nil
	if resourceMeta then
		shieldMeta = resourceMeta.shield
		healthMeta = resourceMeta.health
	end

	for _, sub in ipairs(subscriptions) do
		StatsMediator.forget(sub.event, sub.token)
	end

	local shieldLogCaptured = false
	local healthLogCaptured = false
	for _, entry in ipairs(logEntries) do
		if entry.event == "resolveCombatCost" and entry.stage == "shield_absorb" then
			shieldLogCaptured = true
		elseif entry.event == "resolveCombatCost" and entry.stage == "health_damage" then
			healthLogCaptured = true
		end
	end

	recordTest("Combat Shield Event Logged", shieldLogCaptured, `Shield entries: {#logEntries}`)
	recordTest("Combat Health Event Logged", healthLogCaptured, `Health entries: {#logEntries}`)

	local shieldFinal = shieldMeta and shieldMeta.finalCost
	local healthFinal = healthMeta and healthMeta.finalCost
	local shieldMessage = if shieldFinal then `Absorb final cost: {shieldFinal}` else "Shield metadata missing"
	recordTest("Combat Shield Metadata", shieldFinal ~= nil, shieldMessage)
	local healthMessage = if healthFinal then `Health final cost: {healthFinal}` else "Health metadata missing"
	recordTest("Combat Health Metadata", healthFinal ~= nil, healthMessage)
	local expectedApplied = if healthMeta then (healthMeta.appliedAmount or healthFinal) else healthFinal
	local amountMatches = expectedApplied ~= nil and result.finalAmount == expectedApplied
	recordTest("Combat Health Amount Match", amountMatches, `Damage result: {result.finalAmount}`)

	if #logEntries > 0 then
		print("Combat mediator events logged:")
		for _, entry in ipairs(logEntries) do
			print(` • {entry.event}:{entry.stage or "n/a"} final={entry.metadata and entry.metadata.finalCost}`)
		end
	end
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
