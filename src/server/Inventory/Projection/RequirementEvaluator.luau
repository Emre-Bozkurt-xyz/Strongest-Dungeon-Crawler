--!strict
-- Gear requirements are hard: an item whose requirements are not met cannot be equipped, and an
-- equipped item that stops meeting them is suppressed (gives nothing, and a weapon fights as if
-- unarmed) until they are met again. Otherwise trading a player gear above their level would break
-- progression.
--
-- Attributes from other gear count toward requirements (docs/planning/progression-direction.md,
-- "Attribute requirements"), but never an item's own: `resolveActive` activates items in passes,
-- each counting only the items already active, so a ring can open a shield but two items can never
-- open each other.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Registrar = require(ServerScriptService.Server.Services.Registrar)
local StatsManager = require(ServerScriptService.Server.Stats.StatsManager)
local AttributesManager = require(ServerScriptService.Server.Stats.AttributesManager)
local PlayerDataService = require(ServerScriptService.Server.PlayerData.PlayerDataService)
local CharacterXP = require(ReplicatedStorage.Shared.progression.CharacterXP)
local AttributeTypes = require(ReplicatedStorage.Shared.AttributeTypes)
local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)
local Registry = require(ReplicatedStorage.Shared.items.Registry)
local EquipmentDefUtils = require(ReplicatedStorage.Shared.items.EquipmentDefUtils)
local CapabilityResolver = require(script.Parent.CapabilityResolver)

local RequirementEvaluator = {}

-- Added to the player's attribute values while evaluating, by attribute name.
export type AttributeOffset = { [string]: number }

local attrLookup: { [string]: boolean } = {}
for _, attrName in ipairs(AttributeTypes.AllAttributeNames) do
	attrLookup[attrName] = true
end

-- Read from the save rather than through CharacterService, which would pull combat and NPC modules
-- into the inventory's requires (and a require cycle back through AttributesManager).
local function levelOf(player: Player): number
	local data = PlayerDataService.get(player)
	return CharacterXP.levelOf(if data then data.character.xp else 0)
end

local function attributeValue(player: Player, name: string, offset: AttributeOffset?): number?
	local value = AttributesManager.getAttributeValue(player, name :: any)
	if value == nil then
		return nil
	end
	return value + (if offset then offset[name] or 0 else 0)
end

function RequirementEvaluator.evaluate(
	entityId: string,
	def: ItemTypes.ItemDef,
	offset: AttributeOffset?
): (boolean, string?)
	local requirements = EquipmentDefUtils.getRequirements(def)
	if not requirements then
		return true, nil
	end

	if requirements.level then
		local player = Registrar.getPlayerById(entityId)
		if not player then
			return false, "missing_requirement_level"
		end
		if levelOf(player) < requirements.level then
			return false, "requirement_failed::Level"
		end
	end

	if requirements.attributes then
		for attrName, minValue in pairs(requirements.attributes) do
			local player = Registrar.getPlayerById(entityId)
			if not player then
				return false, `missing_requirement_attribute::{attrName}`
			end
			local value = attributeValue(player, attrName, offset)
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
					value = attributeValue(player, statName, offset)
				end
			else
				value = StatsManager.getStatValue(entityId, statName :: any)
			end
			if value == nil then
				return false, `missing_requirement_stat::{statName}`
			end
			if value < minValue then
				return false, `requirement_failed::{statName}`
			end
		end
	end

	return true, nil
end

-- Which of `slots` are active. `offset` corrects the player's current attribute values to exclude
-- gear (pass the negated totals of what gear currently applies; nil when nothing is applied).
-- Returns active slots, with the attributes each one grants, and the reason for each suppressed one.
function RequirementEvaluator.resolveActive(
	entityId: string,
	slots: { [string]: string },
	itemGetter: (uid: string) -> ItemTypes.ItemInstance?,
	offset: AttributeOffset?
): ({ [string]: true }, { [string]: string })
	local pending: { { slot: string, def: ItemTypes.ItemDef, grants: AttributeOffset } } = {}
	local names: { string } = {}
	for slotName in pairs(slots) do
		table.insert(names, slotName)
	end
	-- A stable order, so the same equipment always resolves the same way.
	table.sort(names)
	for _, slotName in ipairs(names) do
		local inst = itemGetter(slots[slotName])
		local def = inst and Registry.get(inst.itemId)
		if inst and def then
			local grants: AttributeOffset = {}
			for _, entry in ipairs(CapabilityResolver.resolve(def, inst).attributes or {}) do
				grants[entry.target] = (grants[entry.target] or 0) + entry.value
			end
			table.insert(pending, { slot = slotName, def = def, grants = grants })
		end
	end

	local current: AttributeOffset = if offset then table.clone(offset) else {}
	local active: { [string]: true } = {}
	local reasons: { [string]: string } = {}
	local changed = true
	while changed do
		changed = false
		for index = #pending, 1, -1 do
			local entry = pending[index]
			local ok, reason = RequirementEvaluator.evaluate(entityId, entry.def, current)
			if ok then
				active[entry.slot] = true
				reasons[entry.slot] = nil
				for name, amount in pairs(entry.grants) do
					current[name] = (current[name] or 0) + amount
				end
				table.remove(pending, index)
				changed = true
			else
				reasons[entry.slot] = reason or "requirements_not_met"
			end
		end
	end
	return active, reasons
end

return RequirementEvaluator
