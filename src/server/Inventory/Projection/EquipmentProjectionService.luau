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

-- Whether the item in `uid` is equipped and active (its requirements met). Before the first
-- recompute nothing is known, and everything counts as active.
function EquipmentProjectionService.isActive(entityId: string, uid: string): boolean
	local current = currentByEntity[entityId]
	if not current then
		return true
	end
	for _, item in ipairs(current.items) do
		if item.uid == uid then
			return item.active
		end
	end
	return true
end

-- What gear currently adds to each attribute, negated: added to the player's attribute values, it
-- leaves what they have without gear (RequirementEvaluator.resolveActive's offset).
function EquipmentProjectionService.gearAttributeOffset(entityId: string): { [string]: number }
	local offset: { [string]: number } = {}
	local current = currentByEntity[entityId]
	if current then
		for _, entry in ipairs(current.appliedAttributes) do
			offset[entry.target] = (offset[entry.target] or 0) - entry.value
		end
	end
	return offset
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

	-- Cleared above, so the player's attributes hold no gear right now: no offset.
	local slots = equip.slots :: { [string]: string }
	local active, reasons = RequirementEvaluator.resolveActive(entityId, slots, itemGetter)
	for slotName, uid in pairs(slots) do
		local inst = itemGetter(uid)
		local def = inst and Registry.get(inst.itemId)
		if not inst or not def then
			continue
		end
		if not active[slotName] then
			table.insert(items, {
				slot = slotName,
				uid = uid,
				active = false,
				suppressedReason = reasons[slotName],
			})
			continue
		end
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