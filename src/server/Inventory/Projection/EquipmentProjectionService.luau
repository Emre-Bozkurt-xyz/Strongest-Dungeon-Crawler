--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)
local Registry = require(ReplicatedStorage.Shared.items.Registry)
local EquipmentRepository = require(script.Parent.Parent.Domain.EquipmentRepository)
local CapabilityResolver = require(script.Parent.CapabilityResolver)
local RequirementEvaluator = require(script.Parent.RequirementEvaluator)
local ProjectionApplier = require(script.Parent.ProjectionApplier)

local EquipmentProjectionService = {}

local itemGetter: ((uid: string) -> ItemTypes.ItemInstance?)? = nil
local emitter: ((entityId: string, projection: ItemTypes.EquipmentProjectionSnapshot) -> ())? = nil
local currentByEntity: { [string]: ItemTypes.EquipmentProjectionSnapshot } = {}
local versionByEntity: { [string]: number } = {}

function EquipmentProjectionService.setItemGetter(getter: (uid: string) -> ItemTypes.ItemInstance?)
	itemGetter = getter
end

function EquipmentProjectionService.setEmitter(fn: (entityId: string, projection: ItemTypes.EquipmentProjectionSnapshot) -> ())
	emitter = fn
end

function EquipmentProjectionService.get(entityId: string): ItemTypes.EquipmentProjectionSnapshot?
	return currentByEntity[entityId]
end

function EquipmentProjectionService.recompute(entityId: string): ItemTypes.EquipmentProjectionSnapshot
	if not itemGetter then
		error("EquipmentProjectionService: item getter is not configured")
	end

	local previous = currentByEntity[entityId]
	ProjectionApplier.clear(entityId, previous :: any)

	local equip = EquipmentRepository.ensure(entityId)
	local aggregateStats: { ItemTypes.ModifierEntry } = {}
	local aggregateAttrs: { ItemTypes.ModifierEntry } = {}
	local aggregateSkills: { ItemTypes.SkillGrant } = {}
	local aggregateAnim: { ItemTypes.AnimationOverrideEntry } = {}
	local items: { ItemTypes.EquipmentProjectionItemStatus } = {}

	for slotName, uid in pairs(equip.slots) do
		if uid then
			local inst = itemGetter(uid)
			if inst then
				local def = Registry.get(inst.itemId)
				if def then
					local ok, reason = RequirementEvaluator.evaluate(entityId, def)
					if ok then
						local caps = CapabilityResolver.resolve(def, inst)
						if caps.stats then
							for _, entry in ipairs(caps.stats) do
								table.insert(aggregateStats, entry)
							end
						end
						if caps.attributes then
							for _, entry in ipairs(caps.attributes) do
								table.insert(aggregateAttrs, entry)
							end
						end
						if caps.skills then
							for _, grant in ipairs(caps.skills) do
								table.insert(aggregateSkills, grant)
							end
						end
						if caps.animationOverrides then
							for _, entry in ipairs(caps.animationOverrides) do
								table.insert(aggregateAnim, entry)
							end
						end
						table.insert(items, {
							slot = slotName,
							uid = uid,
							active = true,
							suppressedReason = nil,
						})
					else
						table.insert(items, {
							slot = slotName,
							uid = uid,
							active = false,
							suppressedReason = reason,
						})
					end
				end
			end
		end
	end

	local version = (versionByEntity[entityId] or 0) + 1
	versionByEntity[entityId] = version

	local applied = ProjectionApplier.apply(entityId, version, aggregateStats, aggregateAttrs, aggregateSkills, aggregateAnim, items)
	currentByEntity[entityId] = (applied :: any) :: ItemTypes.EquipmentProjectionSnapshot

	if emitter then
		emitter(entityId, currentByEntity[entityId] :: ItemTypes.EquipmentProjectionSnapshot)
	end

	return currentByEntity[entityId] :: ItemTypes.EquipmentProjectionSnapshot
end

return EquipmentProjectionService