--!strict
-- Client-side stats display and handling (dispatcher-based)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Networking = require(ReplicatedStorage.Shared.Networking)
local StatTypeUtil = require(ReplicatedStorage.Shared.StatTypeUtil)
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)

local DEBUG = false

local function debugLog(...)
	if DEBUG then
		print("[StatsClient]", ...)
	end
end

-- Local state for stats
local currentStats: StatTypes.PlayerStats? = nil
local changeSignal = Instance.new("BindableEvent")

type ChangeContext = {
	kind: "snapshot" | "delta",
	delta: any?,
}

local function notifyChange(context: ChangeContext)
	if not currentStats then
		return
	end
	changeSignal:Fire(currentStats, context)
end

local dispatcher = Networking.client()

-- Apply incoming deltas to local state
local function requestStats()
	local ok, serializedOrError = pcall(function()
		return (dispatcher :: any):request("StatsRequest", {})
	end)
	if not ok then
		warn("StatsClient: Failed to request stats:", serializedOrError)
		return
	end
	if serializedOrError == nil then
		warn("StatsClient: Received nil stats payload")
		return
	end

	local okDeserialize, deserialized = pcall(function()
		return StatTypeUtil.deserializeStats(serializedOrError)
	end)
	if okDeserialize then
		currentStats = deserialized
		debugLog("Applied snapshot from request", serializedOrError)
		notifyChange({ kind = "snapshot", delta = nil })
	else
		warn("StatsClient: Failed to deserialize stats:", deserialized)
	end
end

local function onStatsDelta(delta: any)
	-- If this is a full sync, (re)initialize state
	if delta and delta.type == StatTypeUtil.DeltaTypes.FULL_SYNC and delta.data then
		local ok, deserialized = pcall(function()
			return StatTypeUtil.deserializeStats(delta.data)
		end)
		if ok then
			currentStats = deserialized
		else
			warn("StatsClient: Failed to deserialize full_sync:", deserialized)
		end
		notifyChange({ kind = "snapshot" })
		return
	end

	if not currentStats then
		-- If no state yet, proactively request a full sync and skip applying this incremental delta
		-- The server should also push a full_sync on join, but this hardens against ordering races
		requestStats()
		return
	end

	local success = pcall(function()
		StatTypeUtil.applyDelta(currentStats :: StatTypes.PlayerStats, delta)
	end)

	if not success then
		warn("StatsClient: Failed to apply delta")
	else
		-- Print pool values after delta
		if delta and delta.target and currentStats then
			local pool = (currentStats :: any)[delta.target]
			if pool and pool.current then
				print(`  {delta.target}: {pool.current}/{pool.max}`)
			end
		end
		notifyChange({ kind = "delta", delta = delta })
	end
end

-- Request fresh stats data from server
-- requestStats defined above

local _statsDeltaDisconnect = (dispatcher :: any):on("StatsDelta", onStatsDelta)

-- Public API
local StatsClient = {}

function StatsClient.getCurrentStats(): StatTypes.PlayerStats?
	return currentStats
end

function StatsClient.getFormattedStats(): StatTypes.PlayerStats?
	if not currentStats then
		-- Trigger a request and return nil for now
		StatsClient.requestStatsUpdate()
		return nil
	end
	return currentStats
end

function StatsClient.requestStatsUpdate()
	requestStats()
end

function StatsClient.onChanged(callback: (StatTypes.PlayerStats, ChangeContext) -> ()): () -> ()
	local connection = changeSignal.Event:Connect(function(stats, context)
		callback(stats, context)
	end)
	return function()
		if connection.Connected then
			connection:Disconnect()
		end
	end
end

-- Get current value of a pool (e.g., Mana, Stamina, Health)
-- poolType should be a string like "Mana", "Stamina", "Health"
function StatsClient.getPoolCurrent(poolType: string): number?
	if not currentStats then
		return nil
	end
	local pool = (currentStats :: any)[poolType]
	if not pool or type(pool) ~= "table" then
		return nil
	end
	-- Check if it's a pool stat (PoolStatClass has currentValue property)
	if pool.currentValue ~= nil then
		return pool.currentValue
	end
	-- Fallback to old field name for backwards compatibility
	if pool.current ~= nil then
		return pool.current
	end
	return nil
end

-- Get max value of a pool
function StatsClient.getPoolMax(poolType: string): number?
	if not currentStats then
		return nil
	end
	local pool = (currentStats :: any)[poolType]
	if not pool or type(pool) ~= "table" then
		return nil
	end
	-- For pools, max is calculated via getValue() which returns the stat's calculated value
	-- Try calling getValue method if it exists (preserved during serialization)
	if type(pool.getValue) == "function" then
		local ok, result = pcall(function()
			return pool:getValue(currentStats)
		end)
		if ok and type(result) == "number" then
			return result
		end
	end
	-- Fallback: try accessing cached value or baseValue
	if pool._cachedValue ~= nil then
		return pool._cachedValue
	end
	if pool.maxValue ~= nil then
		return pool.maxValue
	end
	if pool.baseValue ~= nil then
		return pool.baseValue
	end
	return nil
end

-- Get a static stat value (e.g., AttackSpeed, PhysicalDamage)
-- statType should be a string like "AttackSpeed", "PhysicalDamage"
function StatsClient.getStatValue(statType: string): number?
	if not currentStats then
		return nil
	end
	local stat = (currentStats :: any)[statType]
	if not stat or type(stat) ~= "table" then
		return nil
	end
	-- Check if it's a static stat (has value field)
	if stat.value == nil then
		return nil
	end
	return stat.value
end

-- Initial request after character loads
local function onCharacterAdded(_char: Model)
	-- slight delay to ensure server has initialized
	task.delay(0.2, requestStats)
end

if Players.LocalPlayer.Character then
	onCharacterAdded(Players.LocalPlayer.Character)
end
Players.LocalPlayer.CharacterAdded:Connect(onCharacterAdded)

return StatsClient
