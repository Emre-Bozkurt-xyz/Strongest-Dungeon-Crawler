--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Registrar = require(ServerScriptService.Server.Services.Registrar)
local StatsManager = require(ServerScriptService.Server.Stats.StatsManager)
local AttributesManager = require(ServerScriptService.Server.Stats.AttributesManager)
local AttributeTypes = require(ReplicatedStorage.Shared.AttributeTypes)
local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)
local EquipmentDefUtils = require(ReplicatedStorage.Shared.items.EquipmentDefUtils)

local RequirementEvaluator = {}

local attrLookup: { [string]: boolean } = {}
for _, attrName in ipairs(AttributeTypes.AllAttributeNames) do
	attrLookup[attrName] = true
end

function RequirementEvaluator.evaluate(entityId: string, def: ItemTypes.ItemDef): (boolean, string?)
	local requirements = EquipmentDefUtils.getRequirements(def)
	if not requirements then
		return true, nil
	end

	if requirements.attributes then
		for attrName, minValue in pairs(requirements.attributes) do
			local player = Registrar.getPlayerById(entityId)
			if not player then
				return false, `missing_requirement_attribute::{attrName}`
			end
			local value = AttributesManager.getAttributeValue(player, attrName)
			if value == nil then
				return false, `missing_requirement_attribute::{attrName}`
			end
			if value < minValue then
				return false, `requirement_failed::{attrName}`
			end
		end
	end

	if requirements.stats then
		for statName, minValue in pairs(requirements.stats) do
			local value = nil
			if attrLookup[statName] then
				local player = Registrar.getPlayerById(entityId)
				if player then
					value = AttributesManager.getAttributeValue(player, statName)
				end
			else
				value = StatsManager.getStatValue(entityId, statName)
			end
			if value == nil then
				return false, `missing_requirement_stat::{statName}`
			end
			if value < minValue then
				return false, `requirement_failed::{statName}`
			end
		end
	end

	-- Level requirement is reserved for future progression data integration.
	return true, nil
end

return RequirementEvaluator
