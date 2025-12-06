--!strict
-- Server-side player attributes management system
-- Handles all attribute modifications and syncing to clients

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Networking = require(ReplicatedStorage.Shared.Networking)
local AttributesConfig = require(script.Parent.Config.AttributesConfig)
local AttributeTypes = require(game.ReplicatedStorage.Shared.AttributeTypes)
local Registrar = require(game.ServerScriptService.Server.Services.Registrar)

-- Import types from central location
type PlayerAttributes = AttributeTypes.PlayerAttributes
type AttributeType = AttributeTypes.AttributeType
type AttributeModifier = AttributeTypes.AttributeModifier

type Trace = {
	id: string,
	clientSentTs: number?,
	serverReceiveTs: number?,
	serverEmitTs: number?,
}

type Delta = {
	system: string,
	type: string,
	target: string,
	data: any,
	timestamp: number,
	trace: Trace?,
	version: number?,
}

local AttributesManager = {}
local playerAttributes: { [Player]: PlayerAttributes } = {}
local pendingTraceByPlayer: { [Player]: Trace } = {}
local attrVersionByPlayer: { [Player]: number } = {}

local ATTRIBUTES_CHANNEL_NAME = "Attributes"
local dispatcher = Networking.server()
local dispatcherAny = dispatcher :: any
dispatcherAny:_ensureChannel(ATTRIBUTES_CHANNEL_NAME)

local profilingEnabled = false

type ProfileToken = { label: string, start: number }

local function profileBegin(label: string): ProfileToken?
	if not profilingEnabled then
		return nil
	end
	return {
		label = label,
		start = os.clock(),
	}
end

local function profileEnd(token: ProfileToken?)
	if not token then
		return
	end
	local durationMs = (os.clock() - token.start) * 1000
	print(string.format("[AttributesManager][PROFILE] %s took %.3f ms", token.label, durationMs))
end

-- Serialize attributes for network transmission
function AttributesManager.serializeAttributes(attributes: PlayerAttributes)
	local serialized = {} :: any

	-- Include available attribute points
	serialized.availableAP = attributes.availableAttributePoints

	-- Process each attribute (excluding availableAttributePoints)
	for attributeName, attribute in pairs(attributes) do
		if attributeName ~= "availableAttributePoints" then
			local totalModifierValue = 0
			local modifiers = attribute:getModifierBreakdown()

			-- Calculate total bonus from all modifiers
			for _, modifier in pairs(modifiers) do
				totalModifierValue += modifier.value
			end

			serialized[attributeName] = {
				base = attribute:getBaseValue(),
				bonus = totalModifierValue,
				current = attribute:getValue(), -- Total (base + bonus)
			}
		end
	end

	return serialized
end

-- Helpers to send deltas
local function sendAttrDelta(player: Player, deltaType: string, target: string, data: any)
	local now = os.clock()
	local ver = (attrVersionByPlayer[player] or 0) + 1
	attrVersionByPlayer[player] = ver
	local delta: any = {
		system = "attributes",
		type = deltaType,
		target = target,
		data = data,
		timestamp = now,
		version = ver,
	}
	-- Attach trace only if present (primarily for spend requests)
	local trace = pendingTraceByPlayer[player]
	if trace then
		delta.trace = {
			id = trace.id,
			clientSentTs = trace.clientSentTs,
			serverReceiveTs = trace.serverReceiveTs or now,
			serverEmitTs = now,
		}
	end
	local options = {
		targets = player,
		qos = "HIGH",
	}
	if trace and trace.id then
		options.traceId = trace.id
	end
	dispatcherAny:emit("AttributesDelta", delta :: Delta, options)
end

local function sendFullSync(player: Player)
	local attrs = playerAttributes[player]
	if not attrs then
		return
	end
	local delta: Delta = {
		system = "attributes",
		type = "full_sync",
		target = "ALL_DATA",
		data = AttributesManager.serializeAttributes(attrs),
		timestamp = os.clock(),
		version = attrVersionByPlayer[player] or 0,
	}
	local profileToken = profileBegin("sendFullSync")
	dispatcherAny:emit("AttributesDelta", delta, {
		targets = player,
		qos = "HIGH",
	})
	profileEnd(profileToken)
end

-- Add a modifier to a player's attribute
function AttributesManager.addModifier(player: Player, attributeType: AttributeType, modifier: AttributeModifier)
	if not playerAttributes[player] then
		warn(`Attempted to add modifier for player {player.Name} who has no attributes initialized`)
		return false
	end

	local attribute = (playerAttributes[player] :: any)[attributeType]
	if not attribute then
		warn(`Attribute {attributeType} not found for player {player.Name}`)
		return false
	end

	attribute:addModifier(modifier)

	-- Send targeted delta update
	sendAttrDelta(player, "modifier_added", attributeType, {
		modifier = modifier,
		newTotal = attribute:getValue(),
		modifierTotal = attribute:getModifierTotal(),
	})

	return true
end

-- Remove a modifier from a player's attribute
function AttributesManager.removeModifier(player: Player, attributeType: AttributeType, source_id: string)
	if not playerAttributes[player] then
		warn(`Attempted to remove modifier for player {player.Name} who has no attributes initialized`)
		return false
	end

	local attribute = (playerAttributes[player] :: any)[attributeType]
	if not attribute then
		warn(`Attribute {attributeType} not found for player {player.Name}`)
		return false
	end

	local removed = attribute:removeModifier(source_id)

	if removed then
		-- Send targeted delta update
		sendAttrDelta(player, "modifier_removed", attributeType, {
			source_id = source_id,
			newTotal = attribute:getValue(),
			modifierTotal = attribute:getModifierTotal(),
		})
	end

	return removed
end

-- Initialize attributes for a new player
local function initializePlayerAttributes(player: Player)
	playerAttributes[player] = AttributesConfig.createDefaultAttributes()
	attrVersionByPlayer[player] = 0

	-- Send initial full sync to player
	sendFullSync(player)
end

-- Clean up when player leaves
local function cleanupPlayerAttributes(player: Player)
	playerAttributes[player] = nil
	attrVersionByPlayer[player] = nil
end

-- Update a player's attribute and notify client
function AttributesManager.setAttribute(player: Player, attributeType: AttributeType, newValue: number)
	if not playerAttributes[player] then
		warn(`Attempted to set attribute for player {player.Name} who has no attributes initialized`)
		return false
	end

	local validatedValue = AttributesConfig.validateAttributeValue(newValue)
	local attribute = (playerAttributes[player] :: any)[attributeType]

	if not attribute then
		warn(`Attribute {attributeType} not found for player {player.Name}`)
		return false
	end

	-- Set the base value using the class method
	attribute:setBaseValue(validatedValue)

	-- Reapply all scaling since attribute values changed
	AttributesManager.applyAllScaling(player)

	-- Send targeted delta update
	sendAttrDelta(player, "attribute_set", attributeType, {
		newBase = validatedValue,
		newTotal = attribute:getValue(),
		modifierTotal = attribute:getModifierTotal(),
	})

	return true
end

-- Add to a player's attribute (useful for leveling up)
function AttributesManager.addToAttribute(player: Player, attributeType: AttributeType, amount: number)
	if not playerAttributes[player] then
		warn(`Attempted to add to attribute for player {player.Name} who has no attributes initialized`)
		return false
	end

	local attribute = (playerAttributes[player] :: any)[attributeType]
	if not attribute then
		warn(`Attribute {attributeType} not found for player {player.Name}`)
		return false
	end

	-- Use the class method to add to base value
	attribute:addToBaseValue(amount)

	-- Reapply all scaling since attribute values changed
	AttributesManager.applyAllScaling(player)

	-- Send targeted delta update
	sendAttrDelta(player, "attribute_added", attributeType, {
		amount = amount,
		newBase = attribute:getBaseValue(),
		newTotal = attribute:getValue(),
		modifierTotal = attribute:getModifierTotal(),
	})

	return true
end

-- Get a player's attribute object
function AttributesManager.getAttribute(player: Player, attributeType: AttributeType)
	if not playerAttributes[player] then
		return nil
	end

	return (playerAttributes[player] :: any)[attributeType]
end

-- Get a player's current attribute value
function AttributesManager.getAttributeValue(player: Player, attributeType: AttributeType): number?
	if not playerAttributes[player] then
		return nil
	end

	local attribute = (playerAttributes[player] :: any)[attributeType]
	return attribute and attribute:getValue() or nil
end

-- Get all attributes for a player
function AttributesManager.getAllAttributes(player: Player): PlayerAttributes?
	return playerAttributes[player]
end

-- Reset all attributes to default values
function AttributesManager.resetAttributes(player: Player)
	if not playerAttributes[player] then
		warn(`Attempted to reset attributes for player {player.Name} who has no attributes initialized`)
		return false
	end

	playerAttributes[player] = AttributesConfig.createDefaultAttributes()

	-- Send full sync since all attributes changed
	sendFullSync(player)

	return true
end

-- Apply all attribute scaling effects to a player's attributes
function AttributesManager.applyAllScaling(player: Player)
	if not playerAttributes[player] then
		warn(`Cannot apply scaling for player {player.Name} - missing attributes`)
		return
	end

	local playerId = Registrar.getPlayerId(player)

	-- Apply milestones; individual stat updates will send their own deltas
	local profileToken = profileBegin("applyAllScaling")
	for _, attributeMilestone in pairs(AttributesConfig.AttributeMilestones) do
		local attribute = AttributesManager.getAttribute(player, attributeMilestone.attribute)
		if not attribute then
			warn(`Attribute {attributeMilestone.attribute} not found for player {player.Name}`)
			continue
		end

		local intelligenceValue = attribute:getValue()

		-- Apply the scaling formula defined in the milestone
		attributeMilestone.applyScaling(playerId, intelligenceValue)
	end
	profileEnd(profileToken)
end

function AttributesManager.setProfilingEnabled(enabled: boolean)
	profilingEnabled = enabled
end

-- Connect player events
Players.PlayerAdded:Connect(initializePlayerAttributes)
Players.PlayerRemoving:Connect(cleanupPlayerAttributes)

-- Request handler (C->S): return full serialized data
dispatcherAny:onRequest("AttributesRequest", function(_payload, _meta, context)
	local player = context.player
	if not player then
		warn("AttributesManager received AttributesRequest without player context")
		return nil
	end
	if not playerAttributes[player] then
		initializePlayerAttributes(player)
	end
	return AttributesManager.serializeAttributes(playerAttributes[player])
end)

-- Handle spend point request (C->S)
dispatcherAny:onRequest("AttributesSpendPoint", function(requestData, _meta, context)
	local player = context.player
	if not player then
		warn("AttributesManager received AttributesSpendPoint without player context")
		return { success = false, error = "no_player" }
	end
	local recvTs = os.clock()
	local traceIn = (requestData and requestData.trace) :: any
	local traceId = traceIn and traceIn.id or ("no-trace")
	pendingTraceByPlayer[player] = {
		id = traceId,
		clientSentTs = traceIn and traceIn.clientSentTs or nil,
		serverReceiveTs = recvTs,
	}
	local target = requestData and requestData.target
	if type(target) ~= "string" then
		-- Clear pending trace quickly since we won't emit any deltas
		task.defer(function()
			pendingTraceByPlayer[player] = nil
		end)
		return { success = false, error = "missing_target" }
	end
	local count = 1
	if requestData and type(requestData.count) == "number" then
		count = math.max(1, math.floor(requestData.count))
	end

	local spent = 0
	for _ = 1, count do
		local ok = (AttributesManager :: any).spendAttributePoint(player, target :: any)
		if not ok then
			break
		end
		spent += 1
	end
	local loopEnd = os.clock()
	-- Clear trace shortly after to allow any last emits to carry it
	task.delay(0.1, function()
		pendingTraceByPlayer[player] = nil
	end)
	-- Build small snapshot for immediate client-side UI update (optional)
	local snapshot: any = nil
	if spent > 0 then
		local attrs = playerAttributes[player]
		local attrObj = (attrs :: any)[target]
		snapshot = {
			availableAP = attrs.availableAttributePoints,
			target = target,
			newBase = attrObj:getBaseValue(),
			newTotal = attrObj:getValue(),
			modifierTotal = attrObj:getModifierTotal(),
			version = attrVersionByPlayer[player] or 0,
		}
		local pendingTrace = pendingTraceByPlayer[player]
		if pendingTrace then
			snapshot.trace = {
				id = pendingTrace.id,
				clientSentTs = pendingTrace.clientSentTs,
				serverReceiveTs = pendingTrace.serverReceiveTs,
				serverEmitTs = loopEnd,
			}
		end
	end
	
	-- Update skill metadata after attribute changes (attributes affect stats which affect costs)
	if spent > 0 then
		task.defer(function()
			local SkillMetadataService = require(script.Parent.Parent.SkillsFramework.SkillMetadataService)
			SkillMetadataService.updateAllSkills(player)
		end)
	end
	
	return { success = spent > 0, spent = spent, snapshot = snapshot, error = spent > 0 and "" or "failed" }
end)

-- Utility: available attribute points
function AttributesManager.getAvailableAttributePoints(player: Player): number
	if not playerAttributes[player] then
		warn(`Attempted to get available points for player {player.Name} who has no attributes initialized`)
		return 0
	end

	return playerAttributes[player].availableAttributePoints
end

-- Set available attribute points for a player
function AttributesManager.setAvailableAttributePoints(player: Player, points: number)
	if not playerAttributes[player] then
		warn(`Attempted to set available points for player {player.Name} who has no attributes initialized`)
		return false
	end

	playerAttributes[player].availableAttributePoints = math.max(0, points)

	-- Send updated attributes to client
	sendFullSync(player)

	return true
end

-- Add available attribute points (e.g., from leveling up)
function AttributesManager.addAvailableAttributePoints(player: Player, points: number)
	if not playerAttributes[player] then
		warn(`Attempted to add available points for player {player.Name} who has no attributes initialized`)
		return false
	end

	local currentPoints = playerAttributes[player].availableAttributePoints
	local newPoints = currentPoints + points

	return AttributesManager.setAvailableAttributePoints(player, newPoints)
end

-- Spend attribute points to increase an attribute
function AttributesManager.spendAttributePoint(player: Player, attributeType: AttributeType): boolean
	if not playerAttributes[player] then
		warn(`Attempted to spend attribute point for player {player.Name} who has no attributes initialized`)
		return false
	end

	local availablePoints = playerAttributes[player].availableAttributePoints
	if availablePoints <= 0 then
		warn(`Player {player.Name} has no available attribute points to spend`)
		return false
	end

	local attribute = (playerAttributes[player] :: any)[attributeType]
	if not attribute then
		warn(`Attribute {attributeType} not found for player {player.Name}`)
		return false
	end

	-- Increase the base value of the attribute
	local currentBase = attribute:getBaseValue()
	local newBase = currentBase + 1

	-- Validate the new value is within bounds
	local validatedValue = AttributesConfig.validateAttributeValue(newBase)
	if validatedValue ~= newBase then
		warn(`Cannot increase {attributeType} for {player.Name} - would exceed maximum value`)
		return false
	end

	-- Apply the changes
	attribute:setBaseValue(newBase)
	playerAttributes[player].availableAttributePoints = availablePoints - 1

	-- Reapply all scaling since attribute values changed
	AttributesManager.applyAllScaling(player)

	-- Send targeted delta update
	sendAttrDelta(player, "attribute_increased", attributeType, {
		newBase = newBase,
		newTotal = attribute:getValue(),
		modifierTotal = attribute:getModifierTotal(),
		availablePoints = availablePoints - 1,
	})

	return true
end

return AttributesManager
