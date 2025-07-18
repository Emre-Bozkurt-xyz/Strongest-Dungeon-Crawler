--!strict
-- AttributesClient.luau
-- Client-side attributes management using centralized NetworkManager

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Imports
local ClientNetworkManager = require(script.Parent.ClientNetworkManager)
local NetworkTypes = require(ReplicatedStorage.Shared.NetworkTypes)

-- Types
type Delta = NetworkTypes.Delta
type AttributesData = {
	availableAP: number,
	Strength: { base: number, bonus: number, current: number },
	Intelligence: { base: number, bonus: number, current: number },
	Dexterity: { base: number, bonus: number, current: number },
	Defense: { base: number, bonus: number, current: number },
	Perception: { base: number, bonus: number, current: number },
}

local player = Players.LocalPlayer

-- Attributes handler for ClientNetworkManager
local attributesHandler = {
	serialize = function(data: any): string
		if not data or type(data) ~= "table" then
			return "{}"
		end
		-- Simple JSON-like serialization for attributes
		local parts = {}
		if data.Attributes then
			local attrs = {}
			for key, value in pairs(data.Attributes) do
				table.insert(attrs, `"{key}": {value}`)
			end
			table.insert(parts, `"Attributes": { { table.concat(attrs, ", ") }}`)
		end
		if data.Level then
			table.insert(parts, `"Level": {data.Level}`)
		end
		if data.Experience then
			table.insert(parts, `"Experience": {data.Experience}`)
		end
		return `{ { table.concat(parts, ", ") }}`
	end,

	deserialize = function(data: any): any
		-- Server sends serialized attribute data, return it as-is for client use
		if data and type(data) == "table" then
			return data
		else
			-- Fallback to default structure
			return {
				availableAP = 5,
				Strength = { base = 0, bonus = 0, current = 0 },
				Intelligence = { base = 0, bonus = 0, current = 0 },
				Dexterity = { base = 0, bonus = 0, current = 0 },
				Defense = { base = 0, bonus = 0, current = 0 },
				Perception = { base = 0, bonus = 0, current = 0 },
			}
		end
	end,

	applyDelta = function(currentData: any, delta: Delta): (boolean, any)
		if not currentData then
			currentData = {
				availableAP = 5,
				Strength = { base = 0, bonus = 0, current = 0 },
				Intelligence = { base = 0, bonus = 0, current = 0 },
				Dexterity = { base = 0, bonus = 0, current = 0 },
				Defense = { base = 0, bonus = 0, current = 0 },
				Perception = { base = 0, bonus = 0, current = 0 },
			}
		end

		local success, result = pcall(function()
			local newData = table.clone(currentData)

			-- Handle full sync (most common for attributes)
			if delta.type == "full_sync" and delta.data then
				-- Replace with the new attribute data
				newData = delta.data
			elseif delta.target == "availableAP" then
				newData.availableAP = delta.data.value or delta.data
			elseif delta.target and newData[delta.target] then
				-- Update specific attribute
				if delta.data.base ~= nil then
					newData[delta.target].base = delta.data.base
				end
				if delta.data.bonus ~= nil then
					newData[delta.target].bonus = delta.data.bonus
				end
				if delta.data.current ~= nil then
					newData[delta.target].current = delta.data.current
				end
			end

			return newData
		end)

		if success then
			print(`✅ AttributesClient: Applied {delta.type} delta for {delta.target or "full_sync"}`)
			-- Notify UI of attribute changes (will implement proper connection later)
			-- TODO: Connect to SystemPanelHandler instance when available
			return true, result
		else
			warn(`❌ AttributesClient: Failed to apply delta for {delta.target or "unknown"}: {result}`)
			return false, currentData
		end
	end,
}

-- Initialize attributes system
local function initializeAttributes()
	-- Register attributes system with ClientNetworkManager
	ClientNetworkManager.registerSystem("attributes", attributesHandler, {
		availableAP = 5,
		Strength = { base = 0, bonus = 0, current = 0 },
		Intelligence = { base = 0, bonus = 0, current = 0 },
		Dexterity = { base = 0, bonus = 0, current = 0 },
		Defense = { base = 0, bonus = 0, current = 0 },
		Perception = { base = 0, bonus = 0, current = 0 },
	})

	print("🏷️ AttributesClient: Initialized with centralized NetworkManager")
end

-- Public API
local AttributesClient = {}

-- Get player attributes from ClientNetworkManager
function AttributesClient.getPlayerAttributes(targetPlayer: Player?): AttributesData?
	local target = targetPlayer or player
	local systemData = ClientNetworkManager.getSystemData("attributes")
	return systemData and systemData[target.UserId] or nil
end

-- Request fresh attributes data from server
function AttributesClient.requestAttributesData()
	-- Request the server to send the latest attributes via ClientNetworkManager
	ClientNetworkManager.requestSystemData("attributes")
end

-- Get current attributes data from ClientNetworkManager
function AttributesClient.getCurrentData()
	return ClientNetworkManager.getSystemData("attributes")
end

-- Get formatted attributes for UI display
function AttributesClient.getFormattedAttributes(): AttributesData?
	local data = AttributesClient.getCurrentData()
	if not data then
		-- Request data if we don't have it yet
		print("🏷️ AttributesClient: No data available, requesting from server")
		AttributesClient.requestAttributesData()
		return nil
	end

	-- Ensure the data matches the expected UI format
	return {
		availableAP = data.availableAP or 0,
		Strength = data.Strength or { base = 0, bonus = 0, current = 0 },
		Intelligence = data.Intelligence or { base = 0, bonus = 0, current = 0 },
		Dexterity = data.Dexterity or { base = 0, bonus = 0, current = 0 },
		Defense = data.Defense or { base = 0, bonus = 0, current = 0 },
		Perception = data.Perception or { base = 0, bonus = 0, current = 0 },
	}
end

-- Initialize when script loads
initializeAttributes()

return AttributesClient
