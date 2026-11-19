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

-- Returns the entry stamped with its sourceId, or nil when the modifier did not apply.
local function applyStatModifier(
	entityId: string,
	entry: ItemTypes.ModifierEntry,
	index: number
): ItemTypes.ModifierEntry?
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
	-- A projection entry must reflect something that actually applied, or clear() will try to
	-- remove a modifier that was never added.
	if not StatsManager.addModifier(entityId, entry.target, modifier) then
		return nil
	end
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

-- Removes the previous projection's stat and attribute modifiers. Granted skills are left for
-- `apply` to reconcile: a skill is a live instance (on the client too, mid-cast perhaps), and
-- removing and re-granting it on every recompute would throw that away for nothing.
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
end

-- The same grant: same skill, same override (overrides come from item definitions, so an unchanged
-- grant is the same table).
local function sameGrant(a: ItemTypes.SkillGrant, b: ItemTypes.SkillGrant): boolean
	return a.skillName == b.skillName and rawequal(a.override, b.override)
end

-- Takes away the previous grants that are not wanted any more and grants the wanted ones that are
-- new. Returns what this projection grants. A grant for a skill the entity already has in its own
-- right is not made, so it is never taken away either.
local function syncSkillGrants(
	entityId: string,
	previous: { ItemTypes.SkillGrant },
	wanted: { ItemTypes.SkillGrant }
): { ItemTypes.SkillGrant }
	local kept: { [number]: boolean } = {}
	for _, grant in ipairs(previous) do
		local stillWanted = false
		for index, want in ipairs(wanted) do
			if not kept[index] and sameGrant(grant, want) then
				kept[index] = true
				stillWanted = true
				break
			end
		end
		if not stillWanted then
			pcall(function()
				SkillsManager.removeSkill(entityId, grant.skillName)
			end)
		end
	end

	local granted: { ItemTypes.SkillGrant } = {}
	for index, grant in ipairs(wanted) do
		if kept[index] and SkillsManager.getSkill(entityId, grant.skillName) then
			table.insert(granted, grant)
		elseif not SkillsManager.getSkill(entityId, grant.skillName) then
			local ok = pcall(function()
				SkillsManager.addSkill(entityId, grant.skillName, grant.override)
			end)
			if ok then
				table.insert(granted, grant)
			end
		end
	end
	return granted
end

function ProjectionApplier.apply(
	entityId: string,
	version: number,
	stats: { ItemTypes.ModifierEntry },
	attributes: { ItemTypes.ModifierEntry },
	skills: { ItemTypes.SkillGrant },
	animationOverrides: { ItemTypes.AnimationOverrideEntry },
	items: { ItemTypes.EquipmentProjectionItemStatus },
	previous: AppliedProjectionState?
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

	local granted = syncSkillGrants(entityId, if previous then previous.grantedSkills else {}, skills)

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
