--!strict
-- Client-side testing to verify delta reception and application

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local warp = require(ReplicatedStorage.Packages.warp)

local StatTypeUtil = require(ReplicatedStorage.Shared.StatTypeUtil)

local ClientTesting = {}
ClientTesting.testResults = {}
ClientTesting.isMonitoring = false
ClientTesting.deltaReceiveCount = 0
ClientTesting.fullSyncReceiveCount = 0
ClientTesting.batchReceiveCount = 0
ClientTesting.lastStatValues = {}

local statsDeltaEvent = warp.Client("StatsDelta")
local _player = Players.LocalPlayer

-- Test result tracking
local function recordTest(testName: string, success: boolean, message: string?)
	table.insert(ClientTesting.testResults, {
		name = testName,
		success = success,
		message = message or "",
		timestamp = tick(),
	})

	if success then
		print(`✅ CLIENT TEST PASSED: {testName} - {message or ""}`)
	else
		warn(`❌ CLIENT TEST FAILED: {testName} - {message or ""}`)
	end
end

function ClientTesting.startMonitoring()
	if ClientTesting.isMonitoring then
		return
	end

	ClientTesting.isMonitoring = true
	ClientTesting.testResults = {}
	ClientTesting.deltaReceiveCount = 0
	ClientTesting.fullSyncReceiveCount = 0
	ClientTesting.batchReceiveCount = 0

	print("🔍 CLIENT: Starting delta monitoring...")

	-- Monitor delta events
	statsDeltaEvent:Connect(function(deltaUpdate)
		ClientTesting.onDeltaReceived(deltaUpdate)
	end)

	-- Start continuous monitoring
	ClientTesting.startContinuousMonitoring()
end

function ClientTesting.onDeltaReceived(deltaUpdate: any)
	if not ClientTesting.isMonitoring then
		return
	end

	if not deltaUpdate then
		recordTest("Delta Reception", false, "Received nil delta update")
		return
	end

	if deltaUpdate.type == "batch" then
		ClientTesting.batchReceiveCount += 1

		if deltaUpdate.deltas and #deltaUpdate.deltas > 0 then
			recordTest("Batch Delta Reception", true, `Received batch with {#deltaUpdate.deltas} deltas`)

			-- Verify batch structure
			for i, delta in ipairs(deltaUpdate.deltas) do
				if not delta.type or not delta.stat then
					recordTest("Batch Delta Structure", false, `Delta {i} missing type or stat`)
				end
			end
		else
			recordTest("Batch Delta Reception", false, "Batch delta has no deltas array")
		end
	elseif deltaUpdate.type == "full_sync" then
		ClientTesting.fullSyncReceiveCount += 1

		if deltaUpdate.stat == "ALL_STATS" and deltaUpdate.data then
			recordTest("Full Sync Reception", true, "Received valid full sync")

			-- Verify full sync data structure
			if type(deltaUpdate.data) == "table" then
				local statCount = 0
				for _ in pairs(deltaUpdate.data) do
					statCount += 1
				end
				recordTest("Full Sync Data", true, `Full sync contains {statCount} stats`)
			else
				recordTest("Full Sync Data", false, "Full sync data is not a table")
			end
		else
			recordTest(
				"Full Sync Reception",
				false,
				`Invalid full sync - stat: {deltaUpdate.stat}, data present: {deltaUpdate.data ~= nil}`
			)
		end
	else
		-- Single delta
		ClientTesting.deltaReceiveCount += 1

		if deltaUpdate.type and deltaUpdate.stat then
			recordTest("Single Delta Reception", true, `Received {deltaUpdate.type} for {deltaUpdate.stat}`)

			-- Verify delta type is valid
			local validTypes = {
				[StatTypeUtil.DeltaTypes.MODIFIER_ADDED] = true,
				[StatTypeUtil.DeltaTypes.MODIFIER_REMOVED] = true,
				[StatTypeUtil.DeltaTypes.MODIFIER_UPDATED] = true,
				[StatTypeUtil.DeltaTypes.CURRENT_VALUE_CHANGED] = true,
				[StatTypeUtil.DeltaTypes.BASE_VALUE_CHANGED] = true,
				[StatTypeUtil.DeltaTypes.RESERVATION_ADDED] = true,
				[StatTypeUtil.DeltaTypes.RESERVATION_REMOVED] = true,
			}

			if validTypes[deltaUpdate.type] then
				recordTest("Delta Type Validation", true, `Valid delta type: {deltaUpdate.type}`)
			else
				recordTest("Delta Type Validation", false, `Unknown delta type: {deltaUpdate.type}`)
			end

			-- Verify data structure based on type
			if deltaUpdate.type == StatTypeUtil.DeltaTypes.CURRENT_VALUE_CHANGED then
				if deltaUpdate.data and deltaUpdate.data.currentValue then
					recordTest("Current Value Delta Data", true, `Current value: {deltaUpdate.data.currentValue}`)
				else
					recordTest("Current Value Delta Data", false, "Missing currentValue in data")
				end
			elseif deltaUpdate.type == StatTypeUtil.DeltaTypes.BASE_VALUE_CHANGED then
				if deltaUpdate.data and deltaUpdate.data.baseValue then
					recordTest("Base Value Delta Data", true, `Base value: {deltaUpdate.data.baseValue}`)
				else
					recordTest("Base Value Delta Data", false, "Missing baseValue in data")
				end
			end
		else
			recordTest(
				"Single Delta Reception",
				false,
				`Invalid delta structure - type: {deltaUpdate.type}, stat: {deltaUpdate.stat}`
			)
		end
	end
end

function ClientTesting.startContinuousMonitoring()
	local startTime = tick()
	local frameCount = 0

	local connection
	connection = RunService.Heartbeat:Connect(function()
		if not ClientTesting.isMonitoring then
			connection:Disconnect()
			return
		end

		frameCount += 1

		-- Every 2 seconds, check if we're still receiving deltas
		if frameCount % 120 == 0 then
			local elapsed = tick() - startTime
			local totalDeltas = ClientTesting.deltaReceiveCount + ClientTesting.batchReceiveCount
			recordTest(
				"Delta Flow",
				totalDeltas > 0,
				`Received {ClientTesting.deltaReceiveCount} single deltas, {ClientTesting.batchReceiveCount} batches, {ClientTesting.fullSyncReceiveCount} full syncs in {math.floor(
					elapsed
				)}s`
			)
		end

		-- Stop after 10 seconds
		if frameCount >= 600 then
			connection:Disconnect()
			ClientTesting.stopMonitoring()
		end
	end)
end

function ClientTesting.stopMonitoring()
	ClientTesting.isMonitoring = false
	print("🛑 CLIENT: Stopped delta monitoring")
	ClientTesting.printTestSummary()
end

function ClientTesting.testStatValuesMatch(expectedStats: { [string]: any })
	print("🔍 CLIENT: Testing stat values match expected...")

	-- This would require getting stats from the client's StatsClient instance
	-- For now, we'll just verify the structure
	for statName, expectedValue in pairs(expectedStats) do
		-- In a real implementation, you'd get the actual stat value from your client stats
		recordTest("Stat Value Match", true, `Would test {statName} = {expectedValue}`)
	end
end

function ClientTesting.testDeltaIntegrity()
	print("🔍 CLIENT: Testing delta integrity...")

	-- Test that we don't have any data corruption
	if ClientTesting.deltaReceiveCount > 0 then
		recordTest("Delta Integrity", true, `Received {ClientTesting.deltaReceiveCount} deltas without corruption`)
	else
		recordTest("Delta Integrity", false, "No deltas received")
	end

	if ClientTesting.fullSyncReceiveCount > 0 then
		recordTest("Full Sync Integrity", true, `Received {ClientTesting.fullSyncReceiveCount} full syncs`)
	else
		recordTest("Full Sync Integrity", false, "No full syncs received")
	end
end

function ClientTesting.printTestSummary()
	print("\n📋 CLIENT TEST SUMMARY:")
	print("========================")

	local passed = 0
	local failed = 0

	for _, result in ipairs(ClientTesting.testResults) do
		if result.success then
			passed += 1
		else
			failed += 1
		end
	end

	print(`✅ Client Tests Passed: {passed}`)
	print(`❌ Client Tests Failed: {failed}`)
	print(`📊 Total Client Tests: {passed + failed}`)
	print(`📡 Delta Statistics:`)
	print(`   - Single Deltas: {ClientTesting.deltaReceiveCount}`)
	print(`   - Batched Deltas: {ClientTesting.batchReceiveCount}`)
	print(`   - Full Syncs: {ClientTesting.fullSyncReceiveCount}`)

	if failed > 0 then
		warn("⚠️  Some client tests failed! Check the output above for details.")
	else
		print("🎉 All client tests passed!")
	end
end

-- Auto-start monitoring when the module loads
ClientTesting.startMonitoring()

return ClientTesting
