--!strict
-- AttributesClient.luau
-- Client-side attributes management using NetRay (per-service)

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Imports
local NetRay = require(ReplicatedStorage.Packages.NetRay)

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

-- NetRay endpoints
local attributesEvent = NetRay:GetEvent("AttributesDelta")
local attributesRequest = NetRay:RegisterRequestEvent("AttributesRequest")

-- Apply incoming delta to local state
local function applyDelta(delta: any)
	if delta.type == "full_sync" and delta.data then
		-- Replace state
		current = delta.data :: AttributesData
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
	elseif (delta.type == "modifier_added" or delta.type == "modifier_removed") and delta.target then
		local target = delta.target
		local d = delta.data
		local c: any = current
		local entry = c[target]
		if entry then
			entry.current = d.newTotal
			entry.bonus = d.modifierTotal
		end
	end
end

-- Listener
if attributesEvent then
	attributesEvent:OnEvent(function(delta)
		local ok = pcall(applyDelta, delta)
		if not ok then
			warn("AttributesClient: Failed to apply delta")
		end
	end)
end

-- Public API
local AttributesClient = {}

function AttributesClient.requestAttributesData()
	attributesRequest
		:Request({})
		:andThen(function(data)
			current = data :: AttributesData
		end)
		:catch(function(err)
			warn("AttributesClient: Failed to request attributes:", err)
		end)
end

function AttributesClient.getCurrentData()
	return current
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
