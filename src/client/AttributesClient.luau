--!strict
-- AttributesClient.luau
-- Client-side attributes management using the custom dispatcher

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Imports
local Networking = require(ReplicatedStorage.Shared.Networking)

-- Types
export type AttributesData = {
	availableAP: number,
	Strength: { base: number, bonus: number, current: number },
	Intelligence: { base: number, bonus: number, current: number },
	Dexterity: { base: number, bonus: number, current: number },
	Defense: { base: number, bonus: number, current: number },
	Perception: { base: number, bonus: number, current: number },
}

local player = Players.LocalPlayer

-- Local state
local current: AttributesData? = nil
local currentVersion: number = 0
local listeners: { [number]: (AttributesData, string, any?) -> () } = {}
local nextListenerId = 0

local ATTRIBUTES_CHANNEL_NAME = "Attributes"
local dispatcher = Networking.client()
local dispatcherAny = dispatcher :: any
dispatcherAny:_ensureChannel(ATTRIBUTES_CHANNEL_NAME)

local function notify(source: string, trace: any?)
	if not current then
		return
	end
	local snapshotListeners = table.clone(listeners)
	for _, cb in pairs(snapshotListeners) do
		cb(current :: AttributesData, source, trace)
	end
end

-- Apply incoming delta to local state
local function applyDelta(delta: any)
	-- Debug: log receive with timing if trace present
	local trace = (delta :: any).trace
	if delta.type == "full_sync" and delta.data then
		-- Replace state
		current = delta.data :: AttributesData
		currentVersion = (delta :: any).version or currentVersion
		notify("full_sync", trace)
		return
	end

	if not current then
		return -- wait for full_sync
	end

	if
		(delta.type == "attribute_increased" or delta.type == "attribute_set" or delta.type == "attribute_added")
		and delta.target
	then
		local target = delta.target
		local d = delta.data
		local c: any = current
		local entry = c[target]
		if entry then
			entry.base = d.newBase
			entry.current = d.newTotal
			entry.bonus = d.modifierTotal
		end
		if d and d.availablePoints ~= nil then
			(current :: AttributesData).availableAP = d.availablePoints
		end
		notify("delta", trace)
	elseif (delta.type == "modifier_added" or delta.type == "modifier_removed") and delta.target then
		local target = delta.target
		local d = delta.data
		local c: any = current
		local entry = c[target]
		if entry then
			entry.current = d.newTotal
			entry.bonus = d.modifierTotal
		end
		notify("delta", trace)
	end
end

-- Listener
local function onAttributesDelta(delta: any, _meta: any)
	-- Version gate BEFORE apply to prevent stale overwrite
	local ver = (delta :: any).version
	if ver then
		if ver <= currentVersion then
			return
		end
		currentVersion = ver
	end

	local ok = pcall(applyDelta, delta)
	if not ok then
		warn("AttributesClient: Failed to apply delta")
	end
end

local _attributesDeltaDisconnect = dispatcherAny:on("AttributesDelta", onAttributesDelta)

-- Public API
local AttributesClient = {}

function AttributesClient.requestAttributesData()
	local ok, resultOrError = pcall(function()
		return dispatcherAny:request("AttributesRequest", {})
	end)
	if not ok then
		warn("AttributesClient: Failed to request attributes:", resultOrError)
		return
	end
	if resultOrError == nil then
		warn("AttributesClient: Received nil attributes payload")
		return
	end
	current = resultOrError :: AttributesData
	notify("request", nil)
end

function AttributesClient.getCurrentData()
	return current
end

function AttributesClient.onChanged(callback: (AttributesData, string, any?) -> ())
	nextListenerId += 1
	local id = nextListenerId
	listeners[id] = callback
	if current then
		callback(current :: AttributesData, "immediate", nil)
	end
	return {
		Disconnect = function()
			listeners[id] = nil
		end,
	}
end

-- Optional: get current version (debug)
function AttributesClient.getVersion(): number
	return currentVersion
end

-- Apply a minimal snapshot with version gating (used by request fast-path)
function AttributesClient.applySnapshot(snap: any)
	if not snap or not current then
		return false
	end
	local ver = snap.version :: number?
	if ver then
		if ver <= currentVersion then
			return false
		end
		currentVersion = ver
	end
	local c: any = current
	local entry = c[snap.target]
	if entry then
		entry.base = snap.newBase
		entry.current = snap.newTotal
		entry.bonus = snap.modifierTotal
	end
	c.availableAP = snap.availableAP
	notify("snapshot", snap.trace)
	return true
end

function AttributesClient.getFormattedAttributes(): AttributesData?
	if not current then
		AttributesClient.requestAttributesData()
		return nil
	end
	return current
end

-- Initial request after character loads
local function onCharacterAdded(_char: Model)
	task.delay(0.2, AttributesClient.requestAttributesData)
end

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)

return AttributesClient
