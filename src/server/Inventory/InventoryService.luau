--!strict
-- InventoryService: server authoritative inventory + equipment state.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Networking = require(ReplicatedStorage.Shared.Networking)
local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)
local Registry = require(ReplicatedStorage.Shared.items.Registry)
local ItemUtils = require(ReplicatedStorage.Shared.items.ItemUtils)
local SharedConfig = require(ReplicatedStorage.Shared.Config)

local Registrar = require(ServerScriptService.Server.Services.Registrar)
local DataManager = require(ServerScriptService.Server.Services.DataManager)
local ItemInstances = require(script.Parent.Domain.ItemInstanceRepository)
local InventoryRepository = require(script.Parent.Domain.InventoryRepository)
local EquipmentRepository = require(script.Parent.Domain.EquipmentRepository)
local InventoryReplicationService = require(script.Parent.Domain.InventoryReplicationService)
local InventoryQueryService = require(script.Parent.Domain.InventoryQueryService)
local LootDropService = require(script.Parent.Domain.LootDropService)
local InventoryCommandService = require(script.Parent.Domain.InventoryCommandService)
local EquipmentProjectionService = require(script.Parent.Projection.EquipmentProjectionService)
local CombatLoadoutService = require(script.Parent.CombatLoadout.CombatLoadoutService)
local EquipmentEquipValidator = require(script.Parent.Validation.EquipmentEquipValidator)
local UseHandlers = require(script.Parent.UseHandlers)

local dispatcher = Networking.server()
local dispatcherAny = dispatcher :: any

local InventoryService = {}
local WorldLootInspectConfig = SharedConfig.WorldLootInspect
local LOOT_SERVER_CONFIG = WorldLootInspectConfig.server

local DEFAULT_CAPACITY = 30

EquipmentProjectionService.setItemGetter(function(uid: string): ItemTypes.ItemInstance?
	return ItemInstances.get(uid)
end)
EquipmentProjectionService.setEmitter(function(entityId: string, projection: ItemTypes.EquipmentProjectionSnapshot)
	InventoryReplicationService.emitProjection(entityId, projection)
end)
CombatLoadoutService.setItemGetter(function(uid: string): ItemTypes.ItemInstance?
	return ItemInstances.get(uid)
end)
CombatLoadoutService.setEmitter(function(entityId: string, loadout: ItemTypes.CombatLoadoutSnapshot)
	InventoryReplicationService.emitLoadout(entityId, loadout)
end)

local function recomputeEquipmentDerived(entityId: string)
	EquipmentProjectionService.recompute(entityId)
	CombatLoadoutService.recompute(entityId)
end

local function buildDropDisplay(inst: ItemTypes.ItemInstance): { displayName: string?, rarity: string?, stackSize: number? }
	local meta = inst.meta
	return {
		displayName = if meta and type(meta.displayName) == "string" then meta.displayName else nil,
		rarity = if meta and type(meta.rarity) == "string" then meta.rarity else nil,
		stackSize = inst.stackSize,
	}
end

local function resolveDropSpawnPosition(entityId: string): Vector3
	local entity = Registrar.getEntityById(entityId)
	if not entity then
		return Vector3.new(0, 3, 0)
	end

	local root = entity:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return entity:GetPivot().Position + Vector3.new(0, LOOT_SERVER_CONFIG.dropHeightOffset, 0)
	end

	local flatForward = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if flatForward.Magnitude <= 1e-4 then
		flatForward = Vector3.new(0, 0, -1)
	else
		flatForward = flatForward.Unit
	end

	local horizontalTarget = root.Position + flatForward * LOOT_SERVER_CONFIG.dropForwardDistance
	local probeOrigin = horizontalTarget + Vector3.new(0, LOOT_SERVER_CONFIG.dropGroundProbeHeight, 0)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { entity }

	local hit = Workspace:Raycast(
		probeOrigin,
		Vector3.new(0, -LOOT_SERVER_CONFIG.dropGroundProbeLength, 0),
		params
	)
	if hit then
		return hit.Position + Vector3.new(0, 0.75, 0)
	end

	return horizontalTarget + Vector3.new(0, LOOT_SERVER_CONFIG.dropHeightOffset, 0)
end

local function canPickupDrop(entityId: string, drop: BasePart): boolean
	local entity = Registrar.getEntityById(entityId)
	if not entity then
		return false
	end
	local root = entity:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	return (root.Position - drop.Position).Magnitude <= LOOT_SERVER_CONFIG.pickupDistance
end

local function spawnDrop(uid: string, position: Vector3, ownerEntityId: string?)
	local inst = ItemInstances.get(uid)
	if not inst then
		return
	end
	LootDropService.spawnDrop(
		uid,
		inst.itemId,
		position,
		ownerEntityId,
		buildDropDisplay(inst),
		function(dropUid: string, dropEntityId: string): boolean
			return InventoryService.pickupDrop(dropUid, dropEntityId)
		end
	)
end

function InventoryService.pickupDrop(uid: string, entityId: string): boolean
	local drop = LootDropService.get(uid)
	if not drop then
		return false
	end
	local inst = ItemInstances.get(uid)
	if not inst then
		LootDropService.cleanup(uid)
		return false
	end
	local ownerEntityId = drop:GetAttribute("OwnerEntityId")
	local claimExpiresAt = drop:GetAttribute("ClaimExpiresAt")
	if type(ownerEntityId) == "string" and ownerEntityId ~= entityId then
		if type(claimExpiresAt) == "number" and os.clock() < claimExpiresAt then
			return false
		end
	end
	if not canPickupDrop(entityId, drop) then
		return false
	end
	local ok = InventoryService.addExistingItem(entityId, uid)
	if ok then
		LootDropService.cleanup(uid)
	end
	return ok
end

local function findEmptySlot(inv: ItemTypes.InventoryState): number?
	return InventoryRepository.findEmptySlot(inv)
end

local function rebuildStacks(inv: ItemTypes.InventoryState)
	InventoryRepository.rebuildStacks(inv)
end

local function emitDeltas(entityId: string, deltas: { ItemTypes.InventoryDelta })
	for _, delta in ipairs(deltas) do
		InventoryReplicationService.emitDelta(entityId, delta)
	end
end

function InventoryService.ensureInventory(entityId: string): ItemTypes.InventoryState
	return InventoryRepository.ensure(entityId, DEFAULT_CAPACITY)
end

function InventoryService.getInventory(entityId: string): ItemTypes.InventoryState?
	return InventoryRepository.get(entityId)
end

function InventoryService.getEquipment(entityId: string): ItemTypes.EquipmentState
	return EquipmentRepository.ensure(entityId)
end

function InventoryService.getSnapshot(entityId: string): ItemTypes.InventorySnapshot
	return InventoryQueryService.snapshot(entityId, {
		inventoryEnsure = function(ownerId: string): ItemTypes.InventoryState
			return InventoryService.ensureInventory(ownerId)
		end,
		equipmentEnsure = function(ownerId: string): ItemTypes.EquipmentState
			return InventoryService.getEquipment(ownerId)
		end,
		itemGet = function(uid: string): ItemTypes.ItemInstance?
			return ItemInstances.get(uid)
		end,
	})
end

function InventoryService.initializePlayer(player: Player)
	local entityId = Registrar.getPlayerId(player)
	if not entityId then
		return
	end

	local saved = DataManager.loadInventory(entityId)
	if saved and type(saved) == "table" then
		local inv = InventoryService.ensureInventory(entityId)
		if type(saved.capacity) == "number" then
			inv.capacity = saved.capacity
		end
		if type(saved.slots) == "table" then
			inv.slots = saved.slots :: { [number]: string? }
		end
		rebuildStacks(inv)
	else
		InventoryService.ensureInventory(entityId)
	end
	EquipmentRepository.ensure(entityId)

	local snapshot = InventoryService.getSnapshot(entityId)
	InventoryReplicationService.emitDelta(entityId, { kind = "inventory_capacity", capacity = snapshot.inventory.capacity })
	for slot, uid in pairs(snapshot.inventory.slots) do
		InventoryReplicationService.emitDelta(entityId, { kind = "inventory_slot", slot = slot, uid = uid })
	end
	for slot, uid in pairs(snapshot.equipment.slots) do
		InventoryReplicationService.emitDelta(entityId, { kind = "equipment_slot", slot = slot, uid = uid })
	end
	for _, item in pairs(snapshot.items) do
		InventoryReplicationService.emitDelta(entityId, { kind = "item_added", item = item })
	end
	InventoryReplicationService.emitSnapshot(entityId, snapshot)
	recomputeEquipmentDerived(entityId)
end

function InventoryService.addItem(entityId: string, itemId: string, count: number, meta: ItemTypes.ItemMeta?): boolean
	local def = Registry.get(itemId)
	if not def then
		return false
	end
	local inv = InventoryService.ensureInventory(entityId)
	local remaining = math.max(0, count)
	local deltas: { ItemTypes.InventoryDelta } = {}

	local stackLimit = if def.stackLimit and def.stackLimit > 0 then def.stackLimit else 1
	if stackLimit > 1 then
		local key = ItemUtils.makeStackKey(itemId, meta, def.stackSensitiveMeta)
		local bucket = inv.stacks[key] or {}
		for _, uid in ipairs(bucket) do
			local inst = ItemInstances.get(uid)
			if inst and inst.stackSize < stackLimit and remaining > 0 then
				local add = math.min(remaining, stackLimit - inst.stackSize)
				inst.stackSize += add
				remaining -= add
				table.insert(deltas, { kind = "item_updated", item = inst })
			end
		end
	end

	while remaining > 0 do
		local slot = findEmptySlot(inv)
		if not slot then
			break
		end
		local size = math.min(remaining, stackLimit)
		local inst = ItemInstances.create(itemId, size, meta)
		if not inst then
			break
		end
		inv.slots[slot] = inst.uid
		table.insert(deltas, { kind = "item_added", item = inst })
		table.insert(deltas, { kind = "inventory_slot", slot = slot, uid = inst.uid })
		remaining -= size
	end

	rebuildStacks(inv)
	emitDeltas(entityId, deltas)
	return remaining == 0
end

local function moveInventoryItem(
	entityId: string,
	fromSlot: number,
	toSlot: number?
): (boolean, string?)
	local inv = InventoryService.ensureInventory(entityId)
	local fromUid = inv.slots[fromSlot]
	if not fromUid then
		return false, "empty_source"
	end
	local destSlot = toSlot or findEmptySlot(inv)
	if not destSlot then
		return false, "inventory_full"
	end
	if destSlot == fromSlot then
		return true, nil
	end
	local destUid = inv.slots[destSlot]
	if destUid then
		inv.slots[destSlot] = fromUid
		inv.slots[fromSlot] = destUid
	else
		inv.slots[destSlot] = fromUid
		inv.slots[fromSlot] = nil
	end
	rebuildStacks(inv)
	emitDeltas(entityId, {
		{ kind = "inventory_slot", slot = fromSlot, uid = inv.slots[fromSlot] },
		{ kind = "inventory_slot", slot = destSlot, uid = inv.slots[destSlot] },
	})
	return true, nil
end

local function moveInventoryToEquipment(
	entityId: string,
	fromSlot: number,
	equipSlot: string
): (boolean, string?)
	local inv = InventoryService.ensureInventory(entityId)
	local equip = EquipmentRepository.ensure(entityId)
	local uid = inv.slots[fromSlot]
	if not uid then
		return false, "empty_source"
	end
	local inst = ItemInstances.get(uid)
	if not inst then
		return false, "missing_item"
	end
	local itemGetter = function(itemUid: string): ItemTypes.ItemInstance?
		return ItemInstances.get(itemUid)
	end
	local valid, reason, outcome = EquipmentEquipValidator.validate(entityId, inst, equipSlot, {
		equipment = equip,
		itemGetter = itemGetter,
	})

	if not valid and outcome and outcome.requiresSecondaryUnequip then
		-- D10: two-handed equip auto-unequips an occupied Secondary, as a single atomic operation
		-- (trap 5). Check inventory space *before* any mutation, and only recompute the derived
		-- combat loadout once both slots have settled -- never leave a half-state where the
		-- secondary is unequipped but the two-hander failed to equip.
		local secondaryUid = equip.slots.Secondary
		if not secondaryUid then
			-- The outcome claimed a conflict but Secondary is empty now (stale read/race) -- fail
			-- loud rather than silently proceeding on an assumption that no longer holds.
			warn(
				`InventoryService.moveInventoryToEquipment: requiresSecondaryUnequip outcome but`
					.. ` Secondary is empty for entity {entityId}`
			)
			return false, reason or "requirements_not_met"
		end

		local destSlot = findEmptySlot(inv)
		if not destSlot then
			return false, "inventory_full"
		end

		-- Nothing has been mutated above this line. Perform both moves together, then recompute
		-- and replicate once.
		local prevMain = equip.slots[equipSlot]
		EquipmentRepository.setSlot(entityId, "Secondary", nil)
		EquipmentRepository.setSlot(entityId, equipSlot, uid)
		inv.slots[destSlot] = secondaryUid
		inv.slots[fromSlot] = prevMain
		rebuildStacks(inv)
		emitDeltas(entityId, {
			{ kind = "equipment_slot", slot = "Secondary", uid = nil },
			{ kind = "equipment_slot", slot = equipSlot, uid = equip.slots[equipSlot] },
			{ kind = "inventory_slot", slot = destSlot, uid = inv.slots[destSlot] },
			{ kind = "inventory_slot", slot = fromSlot, uid = inv.slots[fromSlot] },
		})
		recomputeEquipmentDerived(entityId)
		return true, nil
	end

	if not valid then
		return false, reason
	end

	local prev = equip.slots[equipSlot]
	EquipmentRepository.setSlot(entityId, equipSlot, uid)
	inv.slots[fromSlot] = prev
	rebuildStacks(inv)
	emitDeltas(entityId, {
		{ kind = "equipment_slot", slot = equipSlot, uid = equip.slots[equipSlot] },
		{ kind = "inventory_slot", slot = fromSlot, uid = inv.slots[fromSlot] },
	})
	recomputeEquipmentDerived(entityId)
	return true, nil
end

local function moveEquipmentToInventory(
	entityId: string,
	equipSlot: string,
	toSlot: number?
): (boolean, string?)
	local inv = InventoryService.ensureInventory(entityId)
	local equip = EquipmentRepository.ensure(entityId)
	local uid = equip.slots[equipSlot]
	if not uid then
		return false, "empty_source"
	end
	local destSlot = toSlot or findEmptySlot(inv)
	if not destSlot then
		return false, "inventory_full"
	end
	local destUid = inv.slots[destSlot]
	if destUid then
		local destInst = ItemInstances.get(destUid)
		if not destInst then
			return false, "invalid_swap"
		end
		local valid, reason = EquipmentEquipValidator.validate(entityId, destInst, equipSlot, {
			equipment = equip,
			itemGetter = function(itemUid: string): ItemTypes.ItemInstance?
				return ItemInstances.get(itemUid)
			end,
		})
		if not valid then
			return false, reason or "invalid_swap"
		end
	end
	EquipmentRepository.setSlot(entityId, equipSlot, destUid)
	inv.slots[destSlot] = uid
	rebuildStacks(inv)
	emitDeltas(entityId, {
		{ kind = "equipment_slot", slot = equipSlot, uid = equip.slots[equipSlot] },
		{ kind = "inventory_slot", slot = destSlot, uid = inv.slots[destSlot] },
	})
	recomputeEquipmentDerived(entityId)
	return true, nil
end

local function splitStack(entityId: string, fromSlot: number, count: number, toSlot: number?): (boolean, string?)
	local inv = InventoryService.ensureInventory(entityId)
	local uid = inv.slots[fromSlot]
	if not uid then
		return false, "empty_source"
	end
	local inst = ItemInstances.get(uid)
	if not inst then
		return false, "missing_item"
	end
	if count <= 0 or count >= inst.stackSize then
		return false, "invalid_count"
	end
	local destSlot = toSlot or findEmptySlot(inv)
	if not destSlot then
		return false, "inventory_full"
	end
	local newInst = ItemInstances.create(inst.itemId, count, inst.meta)
	if not newInst then
		return false, "create_failed"
	end
	inst.stackSize -= count
	inv.slots[destSlot] = newInst.uid
	rebuildStacks(inv)
	emitDeltas(entityId, {
		{ kind = "item_updated", item = inst },
		{ kind = "item_added", item = newInst },
		{ kind = "inventory_slot", slot = destSlot, uid = newInst.uid },
	})
	return true, nil
end

local function mergeStacks(entityId: string, fromSlot: number, toSlot: number): (boolean, string?)
	local inv = InventoryService.ensureInventory(entityId)
	local fromUid = inv.slots[fromSlot]
	local toUid = inv.slots[toSlot]
	if not fromUid or not toUid then
		return false, "empty_source"
	end
	local fromInst = ItemInstances.get(fromUid)
	local toInst = ItemInstances.get(toUid)
	if not fromInst or not toInst then
		return false, "missing_item"
	end
	local def = Registry.get(fromInst.itemId)
	if not def or def.id ~= toInst.itemId then
		return false, "different_item"
	end
	if not ItemUtils.canStack(fromInst.meta, toInst.meta, def.stackSensitiveMeta) then
		return false, "meta_mismatch"
	end
	local stackLimit = if def.stackLimit and def.stackLimit > 0 then def.stackLimit else 1
	local space = stackLimit - toInst.stackSize
	if space <= 0 then
		return false, "stack_full"
	end
	local moved = math.min(space, fromInst.stackSize)
	toInst.stackSize += moved
	fromInst.stackSize -= moved
	local deltas: { ItemTypes.InventoryDelta } = {
		{ kind = "item_updated", item = toInst },
	}
	if fromInst.stackSize <= 0 then
		ItemInstances.remove(fromInst.uid)
		inv.slots[fromSlot] = nil
		table.insert(deltas, { kind = "item_removed", uid = fromUid })
		table.insert(deltas, { kind = "inventory_slot", slot = fromSlot, uid = nil })
	else
		table.insert(deltas, { kind = "item_updated", item = fromInst })
	end
	rebuildStacks(inv)
	emitDeltas(entityId, deltas)
	return true, nil
end

local function findOwnedLocation(entityId: string, uid: string): (("inventory" | "equipment")?, number?, string?)
	local inv = InventoryService.ensureInventory(entityId)
	for slot, slotUid in pairs(inv.slots) do
		if slotUid == uid then
			return "inventory", slot, nil
		end
	end
	local equip = EquipmentRepository.ensure(entityId)
	for slot, slotUid in pairs(equip.slots) do
		if slotUid == uid then
			return "equipment", nil, slot
		end
	end
	return nil, nil, nil
end

local function consumeCharges(inst: ItemTypes.ItemInstance): (boolean, string?)
	local meta: ItemTypes.ItemMeta = inst.meta or {}
	local maxCharges = meta.chargesMax
	if maxCharges == nil then
		return false, "no_charges"
	end
	local consumed = meta.chargesConsumed or 1
	local current = meta.chargesCurrent
	if current == nil then
		current = maxCharges
	end
	if current < consumed then
		return false, "no_charges"
	end
	current -= consumed
	meta.chargesCurrent = current
	inst.meta = meta
	return true, nil
end

local function useItem(entityId: string, uid: string): (boolean, string?)
	local inst = ItemInstances.get(uid)
	if not inst then
		return false, "missing_item"
	end
	local def = Registry.get(inst.itemId)
	if not def then
		return false, "missing_def"
	end
	local location, invSlot, equipSlot = findOwnedLocation(entityId, uid)
	if not location then
		return false, "not_owned"
	end

	local deltas: { ItemTypes.InventoryDelta } = {}
	local useOk, useErr = UseHandlers.apply(entityId, inst, def)
	if not useOk then
		return false, useErr
	end

	if inst.meta and inst.meta.chargesMax ~= nil then
		local ok, err = consumeCharges(inst)
		if not ok then
			return false, err
		end
		table.insert(deltas, { kind = "item_updated", item = inst })
	else
		local consumed = 1
		if def.metadata and type(def.metadata.chargesConsumed) == "number" then
			consumed = def.metadata.chargesConsumed
		end
		inst.stackSize -= consumed
		if inst.stackSize <= 0 then
			ItemInstances.remove(uid)
			if location == "inventory" then
				local inv = InventoryService.ensureInventory(entityId)
				local slot = invSlot :: number
				inv.slots[slot] = nil
				table.insert(deltas, { kind = "inventory_slot", slot = slot, uid = nil })
			else
				local equip = EquipmentRepository.ensure(entityId)
				local slot = equipSlot :: string
				EquipmentRepository.setSlot(entityId, slot, nil)
				table.insert(deltas, { kind = "equipment_slot", slot = slot, uid = nil })
			end
			table.insert(deltas, { kind = "item_removed", uid = uid })
		else
			table.insert(deltas, { kind = "item_updated", item = inst })
		end
	end

	local ok, err = useOk, useErr
	if not ok then
		return false, err
	end
	emitDeltas(entityId, deltas)
	if location == "equipment" then
		recomputeEquipmentDerived(entityId)
	end
	return true, nil
end

function InventoryService.addExistingItem(entityId: string, uid: string, toSlot: number?): (boolean, string?)
	local inst = ItemInstances.get(uid)
	if not inst then
		return false, "missing_item"
	end
	local inv = InventoryService.ensureInventory(entityId)
	local slot = toSlot or findEmptySlot(inv)
	if not slot then
		return false, "inventory_full"
	end
	if inv.slots[slot] ~= nil then
		return false, "slot_occupied"
	end
	inv.slots[slot] = uid
	rebuildStacks(inv)
	emitDeltas(entityId, {
		{ kind = "inventory_slot", slot = slot, uid = uid },
	})
	return true, nil
end

local function handleAction(entityId: string, payload: any): (boolean, string?)
	if type(payload) ~= "table" then
		return false, "invalid_payload"
	end
	local action = payload.action
	if action == "move" then
		local from = payload.from
		local to = payload.to
		if from and from.container == "inventory" and to and to.container == "inventory" then
			if type(from.slot) ~= "number" or type(to.slot) ~= "number" then
				return false, "invalid_slot"
			end
			return moveInventoryItem(entityId, from.slot, to.slot)
		end
		if from and from.container == "inventory" and to and to.container == "equipment" then
			if type(from.slot) ~= "number" or type(to.slot) ~= "string" then
				return false, "invalid_slot"
			end
			return moveInventoryToEquipment(entityId, from.slot, to.slot)
		end
		if from and from.container == "equipment" and to and to.container == "inventory" then
			if type(from.slot) ~= "string" or type(to.slot) ~= "number" then
				return false, "invalid_slot"
			end
			return moveEquipmentToInventory(entityId, from.slot, to.slot)
		end
		return false, "invalid_move"
	elseif action == "split" then
		if type(payload.fromSlot) ~= "number" or type(payload.count) ~= "number" then
			return false, "invalid_payload"
		end
		if payload.toSlot ~= nil and type(payload.toSlot) ~= "number" then
			return false, "invalid_payload"
		end
		return splitStack(entityId, payload.fromSlot, payload.count, payload.toSlot)
	elseif action == "merge" then
		if type(payload.fromSlot) ~= "number" or type(payload.toSlot) ~= "number" then
			return false, "invalid_payload"
		end
		return mergeStacks(entityId, payload.fromSlot, payload.toSlot)
	elseif action == "equip" then
		if type(payload.fromSlot) ~= "number" or type(payload.toSlot) ~= "string" then
			return false, "invalid_payload"
		end
		return moveInventoryToEquipment(entityId, payload.fromSlot, payload.toSlot)
	elseif action == "unequip" then
		if type(payload.fromSlot) ~= "string" then
			return false, "invalid_payload"
		end
		if payload.toSlot ~= nil and type(payload.toSlot) ~= "number" then
			return false, "invalid_payload"
		end
		return moveEquipmentToInventory(entityId, payload.fromSlot, payload.toSlot)
	elseif action == "use" then
		if type(payload.uid) ~= "string" then
			return false, "invalid_payload"
		end
		return useItem(entityId, payload.uid)
	elseif action == "drop" then
		if type(payload.uid) ~= "string" then
			return false, "invalid_payload"
		end
		if payload.position ~= nil and typeof(payload.position) ~= "Vector3" then
			return false, "invalid_payload"
		end
		return InventoryService.dropItem(entityId, payload.uid, payload.position)
	elseif action == "pickup" then
		if type(payload.uid) ~= "string" then
			return false, "invalid_payload"
		end
		return InventoryService.pickupDrop(payload.uid, entityId)
	end
	return false, "unknown_action"
end

dispatcherAny:onRequest("InventoryRequest", function(_payload, _meta, context)
	local player = context.player
	if not player then
		return nil
	end
	local entityId = Registrar.getPlayerId(player)
	if not entityId then
		return nil
	end
	local snapshot = InventoryService.getSnapshot(entityId)
	return {
		version = 1,
		kind = "snapshot",
		snapshot = snapshot,
		sequence = 0,
	}
end)

dispatcherAny:onRequest("InventoryCommand", function(payload: ItemTypes.InventoryCommand, _meta, context)
	local player = context.player
	if not player then
		return { ok = false, error = "no_player" }
	end
	local entityId = Registrar.getPlayerId(player)
	if not entityId then
		return { ok = false, error = "no_entity" }
	end
	local ok, err = InventoryCommandService.execute(entityId, payload, function(commandPayload: any): (boolean, string?)
		return handleAction(entityId, commandPayload)
	end)
	return {
		ok = ok,
		error = err,
		projection = EquipmentProjectionService.get(entityId),
		loadout = CombatLoadoutService.get(entityId),
	}
end)

-- Drop helper (stubbed world object representation)
function InventoryService.dropItem(entityId: string, uid: string, _position: Vector3?): boolean
	local inv = InventoryService.ensureInventory(entityId)
	local slotToClear: number? = nil
	for slot, slotUid in pairs(inv.slots) do
		if slotUid == uid then
			slotToClear = slot
			break
		end
	end
	if not slotToClear then
		return false
	end
	inv.slots[slotToClear] = nil
	rebuildStacks(inv)
	emitDeltas(entityId, {
		{ kind = "inventory_slot", slot = slotToClear, uid = nil },
	})
	spawnDrop(uid, resolveDropSpawnPosition(entityId), entityId)
	return true
end

return InventoryService
