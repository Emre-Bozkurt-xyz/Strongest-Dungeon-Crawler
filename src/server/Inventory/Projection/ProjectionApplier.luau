--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)
local ModifierFactories = require(ReplicatedStorage.Shared.Modifiers.Factories)
local Registrar = require(ServerScriptService.Server.Services.Registrar)
local StatsManager = require(ServerScriptService.Server.Stats.StatsManager)
local AttributesManager = require(ServerScriptService.Server.Stats.AttributesManager)
local SkillsManager = require(ServerScriptService.Server.SkillsFramework.SkillsManager)

local ProjectionApplier = {}

export type AppliedProjectionState = {
	entityId: string,
	version: number,
	appliedStats: { ItemTypes.ModifierEntry },
	appliedAttributes: { ItemTypes.ModifierEntry },
	grantedSkills: { ItemTypes.SkillGrant },
	animationOverrides: { ItemTypes.AnimationOverrideEntry },
	items: { ItemTypes.EquipmentProjectionItemStatus },
}

local function makeSource(entityId: string, target: string, entry: ItemTypes.ModifierEntry, index: number): string
	if entry.sourceId and entry.sourceId ~= "" then
		return entry.sourceId
	end
	local id = entry.id or tostring(index)
	return `equipment_proj::{entityId}::{target}::{id}`
end

local function applyStatModifier(entityId: string, entry: ItemTypes.ModifierEntry, index: number)
	local sourceId = makeSource(entityId, entry.target, entry, index)
	local modifier = nil
	if entry.kind == "percent" then
		modifier = ModifierFactories.percentBuff({
			sourceId = sourceId,
			percent = entry.value,
			description = entry.description,
			tags = entry.tags,
			priority = entry.priority,
		})
	elseif entry.kind == "percent_of_stat" then
		local targetStat = entry.meta and entry.meta.targetStat or entry.target
		modifier = ModifierFactories.percentOfStat({
			sourceId = sourceId,
			percent = entry.value,
			targetStat = targetStat,
			description = entry.description,
			tags = entry.tags,
			priority = entry.priority,
		})
	else
		modifier = ModifierFactories.flatAdd({
			sourceId = sourceId,
			amount = entry.value,
			description = entry.description,
			tags = entry.tags,
			priority = entry.priority,
		})
	end
	StatsManager.addModifier(entityId, entry.target, modifier)
	local withSource = table.clone(entry)
	withSource.sourceId = sourceId
	return withSource
end

local function applyAttributeModifier(entityId: string, entry: ItemTypes.ModifierEntry, index: number)
	local player = Registrar.getPlayerById(entityId)
	if not player then
		return nil
	end
	local sourceId = makeSource(entityId, entry.target, entry, index)
	AttributesManager.addModifier(player, entry.target, {
		value = entry.value,
		source_id = sourceId,
		description = entry.description,
	})
	local withSource = table.clone(entry)
	withSource.sourceId = sourceId
	return withSource
end

function ProjectionApplier.clear(entityId: string, previous: AppliedProjectionState?)
	if not previous then
		return
	end
	for _, entry in ipairs(previous.appliedStats) do
		if entry.sourceId then
			StatsManager.removeModifier(entityId, entry.target, entry.sourceId)
		end
	end
	local player = Registrar.getPlayerById(entityId)
	if player then
		for _, entry in ipairs(previous.appliedAttributes) do
			if entry.sourceId then
				AttributesManager.removeModifier(player, entry.target, entry.sourceId)
			end
		end
	end
	for _, grant in ipairs(previous.grantedSkills) do
		pcall(function()
			SkillsManager.removeSkill(entityId, grant.skillName)
		end)
	end
end

function ProjectionApplier.apply(
	entityId: string,
	version: number,
	stats: { ItemTypes.ModifierEntry },
	attributes: { ItemTypes.ModifierEntry },
	skills: { ItemTypes.SkillGrant },
	animationOverrides: { ItemTypes.AnimationOverrideEntry },
	items: { ItemTypes.EquipmentProjectionItemStatus }
): AppliedProjectionState
	local appliedStats: { ItemTypes.ModifierEntry } = {}
	for i, entry in ipairs(stats) do
		table.insert(appliedStats, applyStatModifier(entityId, entry, i))
	end

	local appliedAttrs: { ItemTypes.ModifierEntry } = {}
	for i, entry in ipairs(attributes) do
		local applied = applyAttributeModifier(entityId, entry, i)
		if applied then
			table.insert(appliedAttrs, applied)
		end
	end

	local granted: { ItemTypes.SkillGrant } = {}
	for _, grant in ipairs(skills) do
		if not SkillsManager.getSkill(entityId, grant.skillName) then
			local ok = pcall(function()
				SkillsManager.addSkill(entityId, grant.skillName, grant.override)
			end)
			if ok then
				table.insert(granted, grant)
			end
		end
	end

	return {
		entityId = entityId,
		version = version,
		appliedStats = appliedStats,
		appliedAttributes = appliedAttrs,
		grantedSkills = granted,
		animationOverrides = table.clone(animationOverrides),
		items = table.clone(items),
	}
end

return ProjectionApplier
