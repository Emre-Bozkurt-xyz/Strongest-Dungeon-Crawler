--!strict
-- Centralized Network Manager for Delta-based Communication
-- Handles all client-server communication for game systems

local Players = game:GetService("Players")
local warp = require(game.ReplicatedStorage.Packages.warp)

-- Import shared types
local NetworkTypes = require(game.ReplicatedStorage.Shared.NetworkTypes)
export type DeltaData = NetworkTypes.DeltaData
export type Delta = NetworkTypes.Delta
export type BatchedDeltas = NetworkTypes.BatchedDeltas
export type SystemHandler = NetworkTypes.SystemHandler

local NetworkManager = {}

-- Debug configuration
local DEBUG = false -- Set to false to disable debug logging

-- Player-specific state
local playerBatching: { [Player]: { [string]: boolean } } = {} -- Track batching per system per player
local pendingDeltas: { [Player]: { [string]: { Delta } } } = {} -- Queued deltas per system per player
local systemHandlers: { [string]: SystemHandler } = {} -- Registered system handlers

-- Warp events
local networkDeltaEvent = warp.Server("NetworkDelta") -- Single event for all systems
local networkRequestEvent = warp.Server("NetworkRequest") -- System data requests

-- Create a delta
function NetworkManager.createDelta(system: string, deltaType: string, target: string, data: DeltaData): Delta
	return {
		system = system,
		type = deltaType,
		target = target,
		data = data,
		timestamp = tick(),
	}
end

-- Register a system with the network manager
function NetworkManager.registerSystem(systemName: string, handler: SystemHandler)
	systemHandlers[systemName] = handler
	if DEBUG then
		print(`📡 NetworkManager: Registered system '{systemName}'`)
	end
end

-- Enable batching for a specific system for a player
function NetworkManager.enableBatching(player: Player, system: string)
	if not playerBatching[player] then
		playerBatching[player] = {}
	end
	if not pendingDeltas[player] then
		pendingDeltas[player] = {}
	end

	playerBatching[player][system] = true
	pendingDeltas[player][system] = {}

	if DEBUG then
		print(`📦 NetworkManager: Enabled batching for {player.Name}'s {system} system`)
	end
end

-- Disable batching and send all pending deltas for a system
function NetworkManager.disableBatching(player: Player, system: string)
	if not playerBatching[player] or not playerBatching[player][system] then
		return -- Batching wasn't enabled
	end

	playerBatching[player][system] = false

	local deltas = pendingDeltas[player][system]
	if deltas and #deltas > 0 then
		-- Send as batch
		local batch: BatchedDeltas = {
			type = "batch",
			system = system,
			deltas = deltas,
			timestamp = tick(),
		}

		networkDeltaEvent:Fire(true, player, batch)
		if DEBUG then
			print(`📤 NetworkManager: Sent batch of {#deltas} deltas for {player.Name}'s {system} system`)
		end
	end

	-- Clear pending deltas
	pendingDeltas[player][system] = {}
end

-- Send a delta (either immediately or queue for batching)
function NetworkManager.sendDelta(player: Player, delta: Delta)
	-- Check if batching is enabled for this system
	if playerBatching[player] and playerBatching[player][delta.system] then
		-- Add to pending deltas
		table.insert(pendingDeltas[player][delta.system], delta)
		if DEBUG then
			print(`📦 NetworkManager: Queued {delta.type} delta for {player.Name}'s {delta.system}.{delta.target}`)
		end
	else
		-- Send immediately
		networkDeltaEvent:Fire(true, player, delta)
		if DEBUG then
			print(`📤 NetworkManager: Sent {delta.type} delta for {player.Name}'s {delta.system}.{delta.target}`)
		end
	end
end

-- Send a full sync for a system
function NetworkManager.sendFullSync(player: Player, system: string, data: any)
	local handler = systemHandlers[system]
	if not handler then
		warn(`NetworkManager: No handler registered for system '{system}'`)
		return
	end

	local serializedData = handler.serialize(data)
	local fullSyncDelta = NetworkManager.createDelta(system, "full_sync", "ALL_DATA", serializedData)

	networkDeltaEvent:Fire(true, player, fullSyncDelta)
	if DEBUG then
		print(`🔄 NetworkManager: Sent full sync for {player.Name}'s {system} system`)
	end
end

function NetworkManager.invokeSignal(system: string, data: any)

	return warp.Signal(system .. "Signal"):Invoke(system, data)
end

-- Handle system data requests from clients
local function handleNetworkRequest(player: Player, isRequest: boolean, data: any)
	if isRequest then
		-- This is a data request
		local system = data :: string

		if DEBUG then
			print(`📥 NetworkManager: {player.Name} requested {system} data`)
		end

		-- Systems can listen to this and respond with sendFullSync
		local requestSignal = warp.Signal(`{system}FulLSyncRequest`)
		requestSignal:Fire(player)
	else
		-- This is a delta from the client
		local delta = data :: any

		if DEBUG then
			print(`📤 NetworkManager: {player.Name} sent {delta.type} delta for {delta.system}.{delta.target}`)
		end

		-- Get the handler for this system
		local handler = systemHandlers[delta.system]
		if not handler then
			warn(`NetworkManager: No handler for system '{delta.system}'`)
			return
		end

		-- Apply the delta using the system's handler
		local success = handler.applyDelta(nil, delta)
		if DEBUG then
			print(`📊 NetworkManager: Delta application ${success and "succeeded" or "failed"} for {player.Name}`)
		end
	end
end

-- Initialize player networking state
local function initializePlayerNetworking(player: Player)
	playerBatching[player] = {}
	pendingDeltas[player] = {}
	if DEBUG then
		print(`🔌 NetworkManager: Initialized networking for {player.Name}`)
	end
end

-- Clean up player networking state
local function cleanupPlayerNetworking(player: Player)
	playerBatching[player] = nil
	pendingDeltas[player] = nil
	if DEBUG then
		print(`🔌 NetworkManager: Cleaned up networking for {player.Name}`)
	end
end

-- Utility: Enable batching for multiple systems
function NetworkManager.enableMultiSystemBatching(player: Player, systems: { string })
	for _, system in ipairs(systems) do
		NetworkManager.enableBatching(player, system)
	end
end

-- Utility: Disable batching for multiple systems
function NetworkManager.disableMultiSystemBatching(player: Player, systems: { string })
	for _, system in ipairs(systems) do
		NetworkManager.disableBatching(player, system)
	end
end

-- Advanced: Cross-system batching (mix stats + attributes in one batch)
function NetworkManager.enableGlobalBatching(_player: Player)
	-- This would require a more complex system where we batch across all systems
	-- For now, let's keep it simple with per-system batching
	if DEBUG then
		print(`🌐 NetworkManager: Global batching not yet implemented`)
	end
end

-- Toggle debug mode
function NetworkManager.setDebug(enabled: boolean)
	DEBUG = enabled
	if DEBUG then
		print("📡 NetworkManager: Debug mode enabled")
	else
		print("📡 NetworkManager: Debug mode disabled")
	end
end

-- Get current debug state
function NetworkManager.isDebugEnabled(): boolean
	return DEBUG
end

-- Debug: Get current batching status
function NetworkManager.getBatchingStatus(player: Player): { [string]: boolean }?
	return playerBatching[player]
end

-- Debug: Get pending deltas count
function NetworkManager.getPendingDeltasCount(player: Player): { [string]: number }?
	if not pendingDeltas[player] then
		return nil
	end

	local counts = {}
	for system, deltas in pairs(pendingDeltas[player]) do
		counts[system] = #deltas
	end
	return counts
end

-- Connect events
networkRequestEvent:Connect(handleNetworkRequest)

-- Connect player events
Players.PlayerAdded:Connect(initializePlayerNetworking)
Players.PlayerRemoving:Connect(cleanupPlayerNetworking)

print("📡 NetworkManager initialized")

return NetworkManager
