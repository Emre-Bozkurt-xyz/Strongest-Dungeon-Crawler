--!strict

local Players = game:GetService("Players")
local warp = require(game.ReplicatedStorage.Packages.warp)

-- Import shared types
local NetworkTypes = require(game.ReplicatedStorage.Shared.NetworkTypes)
type DeltaData = NetworkTypes.DeltaData
type Delta = NetworkTypes.Delta
type BatchedDeltas = NetworkTypes.BatchedDeltas
type SystemHandler = NetworkTypes.SystemHandler

local ClientNetworkManager = {}

-- Debug configuration
local DEBUG = false -- Set to false to disable debug logging

-- System data storage
local systemData: { [string]: any } = {} -- Current data for each system
local systemHandlers: { [string]: SystemHandler } = {} -- Registered system handlers

-- Warp events
local networkDeltaEvent = warp.Client("NetworkDelta")
local networkRequestEvent = warp.Client("NetworkRequest")

-- Statistics
local deltaStats = {
	received = 0,
	applied = 0,
	failed = 0,
	batches = 0,
	fullSyncs = 0,
}

-- Apply a delta to a specific system
local function applyDeltaToSystem(delta: Delta, handler: SystemHandler): boolean
	if delta.type == "full_sync" then
		-- Handle full sync
		deltaStats.fullSyncs += 1

		if delta.target == "ALL_DATA" and delta.data then
			systemData[delta.system] = handler.deserialize(delta.data)
			if DEBUG then
				print(`📦 ClientNetworkManager: Full sync applied for {delta.system}`)
			end
			return true
		else
			warn(`ClientNetworkManager: Invalid full sync structure for {delta.system}`)
			return false
		end
	else
		-- Handle incremental delta
		if not systemData[delta.system] then
			warn(`ClientNetworkManager: No data for system '{delta.system}' - requesting full sync`)
			ClientNetworkManager.requestSystemData(delta.system)
			return false
		end

		local success, newData = handler.applyDelta(systemData[delta.system], delta)
		if success and newData then
			systemData[delta.system] = newData
		end
		return success
	end
end

-- Register a system with the client network manager
function ClientNetworkManager.registerSystem(systemName: string, handler: SystemHandler, initialData: any?)
	systemHandlers[systemName] = handler
	systemData[systemName] = initialData or {}
	print(`📱 ClientNetworkManager: Registered system '{systemName}'`)
end

-- Request data for a specific system
function ClientNetworkManager.requestSystemData(systemName: string)
	networkRequestEvent:Fire(true, true, systemName)
	if DEBUG then
		print(`📥 ClientNetworkManager: Requested {systemName} data from server`)
	end
end

-- Send a delta to the server
function ClientNetworkManager.sendDelta(delta: Delta)
	networkRequestEvent:Fire(false, false, delta)
	if DEBUG then
		print(`📤 ClientNetworkManager: Sent {delta.type} delta for {delta.system}.{delta.target}`)
	end
end

-- Get current data for a system
function ClientNetworkManager.getSystemData(systemName: string): any?
	return systemData[systemName]
end

-- Handle incoming deltas
local function handleNetworkDelta(deltaOrBatch: Delta | BatchedDeltas)
	deltaStats.received += 1

	if deltaOrBatch.type == "batch" then
		-- Handle batched deltas
		deltaStats.batches += 1
		local batch = deltaOrBatch :: BatchedDeltas

		local handler = systemHandlers[batch.system]
		if not handler then
			warn(`ClientNetworkManager: No handler for system '{batch.system}'`)
			deltaStats.failed += 1
			return
		end

		local successCount = 0
		for _, delta in ipairs(batch.deltas) do
			if applyDeltaToSystem(delta, handler) then
				successCount += 1
			end
		end

		deltaStats.applied += successCount
		deltaStats.failed += (#batch.deltas - successCount)

		if DEBUG then
			print(`📦 ClientNetworkManager: Applied {successCount}/{#batch.deltas} deltas for {batch.system}`)
		end

		-- Emit system update signal
		local updateSignal = warp.Signal(`{batch.system}Updated`)
		updateSignal:Fire(systemData[batch.system])
	else
		-- Handle single delta
		local delta = deltaOrBatch :: Delta

		local handler = systemHandlers[delta.system]
		if not handler then
			warn(`ClientNetworkManager: No handler for system '{delta.system}'`)
			deltaStats.failed += 1
			return
		end

		if applyDeltaToSystem(delta, handler) then
			deltaStats.applied += 1
			if DEBUG then
				print(`📤 ClientNetworkManager: Applied {delta.type} delta for {delta.system}.{delta.target}`)
			end

			-- Emit system update signal
			local updateSignal = warp.Signal(`{delta.system}Updated`)
			updateSignal:Fire(systemData[delta.system])
		else
			deltaStats.failed += 1
		end
	end
end

-- Get networking statistics
function ClientNetworkManager.getStats(): typeof(deltaStats)
	return {
		received = deltaStats.received,
		applied = deltaStats.applied,
		failed = deltaStats.failed,
		batches = deltaStats.batches,
		fullSyncs = deltaStats.fullSyncs,
		successRate = deltaStats.received > 0 and (deltaStats.applied / deltaStats.received * 100) or 0,
	}
end

-- Reset statistics
function ClientNetworkManager.resetStats()
	deltaStats = {
		received = 0,
		applied = 0,
		failed = 0,
		batches = 0,
		fullSyncs = 0,
	}
end

-- Debug: Print current system data
function ClientNetworkManager.debugSystemData(systemName: string?)
	if systemName then
		print(`🔍 ClientNetworkManager: {systemName} data:`, systemData[systemName])
	else
		print(`🔍 ClientNetworkManager: All system data:`, systemData)
	end
end

-- Connect to delta events
networkDeltaEvent:Connect(handleNetworkDelta)

-- Auto-request data for all registered systems when player spawns
local function onPlayerAdded()
	wait(1) -- Give systems time to register

	for systemName, _ in pairs(systemHandlers) do
		ClientNetworkManager.requestSystemData(systemName)
	end

	print(`📱 ClientNetworkManager: Requested initial data for all systems`)
end

-- Toggle debug mode
function ClientNetworkManager.setDebug(enabled: boolean)
	DEBUG = enabled
	if DEBUG then
		print("📱 ClientNetworkManager: Debug mode enabled")
	else
		print("📱 ClientNetworkManager: Debug mode disabled")
	end
end

-- Get current debug state
function ClientNetworkManager.isDebugEnabled(): boolean
	return DEBUG
end

if Players.LocalPlayer then
	onPlayerAdded()
else
	Players.PlayerAdded:Connect(onPlayerAdded)
end

print("📱 ClientNetworkManager initialized")

return ClientNetworkManager
