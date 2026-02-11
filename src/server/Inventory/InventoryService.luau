--!strict
-- InventoryService: server authoritative inventory + equipment state.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Networking = require(ReplicatedStorage.Shared.Networking)
local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)
local Registry = require(ReplicatedStorage.Shared.items.Registry)
local ItemUtils = require(ReplicatedStorage.Shared.items.ItemUtils)

local Registrar = require(ServerScriptService.Server.Services.Registrar)
local DataManager = require(ServerScriptService.Server.Services.DataManager)
local ItemInstances = require(script.Parent.ItemInstances)
local EquipmentService = require(script.Parent.EquipmentService)
local UseHandlers = require(script.Parent.UseHandlers)

local dispatcher = Networking.server()
local dispatcherAny = dispatcher :: any

local InventoryService = {}

local DEFAULT_CAPACITY = 30

local inventories: { [string]: ItemTypes.InventoryState? } = {}
local dropsByUid: { [string]: BasePart } = {}

local function getDropFolder(): Folder
	local folder = Workspace:FindFirstChild("ItemDrops")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "ItemDrops"
		folder.Parent = Workspace
	end
	return folder :: Folder
end

local function cleanupDrop(uid: string)
	local part = dropsByUid[uid]
	if part then
		part:Destroy()
	end
	dropsByUid[uid] = nil
end

local function attachPrompt(drop: BasePart, ownerEntityId: string?)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pick Up"
	prompt.ObjectText = "Item"
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 8
	prompt.Parent = drop

	prompt.Triggered:Connect(function(player)
		local entityId = Registrar.getPlayerId(player)
		if not entityId then
			return
		end
		if ownerEntityId and ownerEntityId ~= entityId then
			return
		end
		local uid = drop:GetAttribute("ItemUid")
		if type(uid) ~= "string" then
			return
		end
		InventoryService.pickupDrop(uid, entityId)
	end)
end

local function spawnDrop(uid: string, position: Vector3, ownerEntityId: string?)
	local inst = ItemInstances.get(uid)
	if not inst then
		return
	end
	local def = Registry.get(inst.itemId)
	local dropFolder = getDropFolder()

	if dropsByUid[uid] then
		cleanupDrop(uid)
	end

	local part = Instance.new("Part")
	part.Name = "ItemDrop"
	part.Size = Vector3.new(1, 1, 1)
	part.Anchored = true
	part.CanCollide = false
	part.Position = position
	part:SetAttribute("ItemUid", uid)
	part:SetAttribute("ItemId", inst.itemId)
	if ownerEntityId then
		part:SetAttribute("OwnerEntityId", ownerEntityId)
	end
	if def and def.name then
		part:SetAttribute("ItemName", def.name)
	end
	part.Parent = dropFolder
	CollectionService:AddTag(part, "LootDrop")
	dropsByUid[uid] = part

	attachPrompt(part, ownerEntityId)
end

function InventoryService.pickupDrop(uid: string, entityId: string): boolean
	local drop = dropsByUid[uid]
	if not drop then
		return false
	end
	local inst = ItemInstances.get(uid)
	if not inst then
		cleanupDrop(uid)
		return false
	end
	local ownerEntityId = drop:GetAttribute("OwnerEntityId")
	if type(ownerEntityId) == "string" and ownerEntityId ~= entityId then
		return false
	end
	local ok = InventoryService.addExistingItem(entityId, uid)
	if ok then
		cleanupDrop(uid)
	end
	return ok
end

local function findEmptySlot(inv: ItemTypes.InventoryState): number?
	for i = 1, inv.capacity do
		if inv.slots[i] == nil then
			return i
		end
	end
	return nil
end

local function rebuildStacks(inv: ItemTypes.InventoryState)
	inv.stacks = {}
	for _, uid in pairs(inv.slots) do
		if uid then
			local inst = ItemInstances.get(uid)
			if inst then
				local def = Registry.get(inst.itemId)
				if def then
					local key = ItemUtils.makeStackKey(inst.itemId, inst.meta, def.stackSensitiveMeta)
					inv.stacks[key] = inv.stacks[key] or {}
					table.insert(inv.stacks[key], uid)
				end
			end
		end
	end
end

local function emitDelta(entityId: string, delta: ItemTypes.InventoryDelta)
	if not Registrar.isPlayerEntity(entityId) then
		return
	end
	local player = Registrar.getPlayerById(entityId)
	if not player then
		return
	end
	dispatcherAny:emit("InventoryDelta", delta, { targets = player })
end

local function emitDeltas(entityId: string, deltas: { ItemTypes.InventoryDelta })
	for _, delta in ipairs(deltas) do
		emitDelta(entityId, delta)
	end
end

function InventoryService.ensureInventory(entityId: string): ItemTypes.InventoryState
	local inv = inventories[entityId]
	if inv then
		return inv
	end
	local slots: { [number]: string? } = {}
	local stacks: { [string]: { string } } = {}
	inv = {
		ownerId = entityId,
		capacity = DEFAULT_CAPACITY,
		slots = slots,
		stacks = stacks,
	}
	for i = 1, DEFAULT_CAPACITY do
		inv.slots[i] = nil
	end
	inventories[entityId] = inv
	return inv
end

function InventoryService.getInventory(entityId: string): ItemTypes.InventoryState?
	return inventories[entityId]
end

function InventoryService.getEquipment(entityId: string): ItemTypes.EquipmentState
	return EquipmentService.ensure(entityId)
end

function InventoryService.getSnapshot(entityId: string): ItemTypes.InventorySnapshot
	local inv = InventoryService.ensureInventory(entityId)
	local equip = EquipmentService.ensure(entityId)
	local items: { [string]: ItemTypes.ItemInstance } = {}
	for _, uid in pairs(inv.slots) do
		if uid then
			local inst = ItemInstances.get(uid)
			if inst then
				items[uid] = inst
			end
		end
	end
	for _, uid in pairs(equip.slots) do
		if uid then
			local inst = ItemInstances.get(uid)
			if inst then
				items[uid] = inst
			end
		end
	end
	return {
		items = items,
		inventory = inv,
		equipment = equip,
	}
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
	EquipmentService.ensure(entityId)

	local snapshot = InventoryService.getSnapshot(entityId)
	dispatcherAny:emit("InventoryDelta", { kind = "inventory_capacity", capacity = snapshot.inventory.capacity }, {
		targets = player,
	})
	for slot, uid in pairs(snapshot.inventory.slots) do
		dispatcherAny:emit("InventoryDelta", { kind = "inventory_slot", slot = slot, uid = uid }, { targets = player })
	end
	for slot, uid in pairs(snapshot.equipment.slots) do
		dispatcherAny:emit("InventoryDelta", { kind = "equipment_slot", slot = slot, uid = uid }, { targets = player })
	end
	for _, item in pairs(snapshot.items) do
		dispatcherAny:emit("InventoryDelta", { kind = "item_added", item = item }, { targets = player })
	end
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
	local equip = EquipmentService.ensure(entityId)
	local uid = inv.slots[fromSlot]
	if not uid then
		return false, "empty_source"
	end
	local inst = ItemInstances.get(uid)
	if not inst then
		return false, "missing_item"
	end
	if not EquipmentService.canEquip(inst.itemId, equipSlot) then
		return false, "invalid_slot"
	end
	local prev = equip.slots[equipSlot]
	equip.slots[equipSlot] = uid
	inv.slots[fromSlot] = prev
	rebuildStacks(inv)
	emitDeltas(entityId, {
		{ kind = "equipment_slot", slot = equipSlot, uid = equip.slots[equipSlot] },
		{ kind = "inventory_slot", slot = fromSlot, uid = inv.slots[fromSlot] },
	})
	return true, nil
end

local function moveEquipmentToInventory(
	entityId: string,
	equipSlot: string,
	toSlot: number?
): (boolean, string?)
	local inv = InventoryService.ensureInventory(entityId)
	local equip = EquipmentService.ensure(entityId)
	local uid = equip.slots[equipSlot]
	if not uid then
		return false, "empty_source"
	end
	local destSlot = toSlot or findEmptySlot(inv)
	if not destSlot then
		return false, "inventory_full"
	end
	local destUid = inv.slots[destSlot]
	equip.slots[equipSlot] = destUid
	inv.slots[destSlot] = uid
	rebuildStacks(inv)
	emitDeltas(entityId, {
		{ kind = "equipment_slot", slot = equipSlot, uid = equip.slots[equipSlot] },
		{ kind = "inventory_slot", slot = destSlot, uid = inv.slots[destSlot] },
	})
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
	local equip = EquipmentService.ensure(entityId)
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
				local equip = EquipmentService.ensure(entityId)
				local slot = equipSlot :: string
				equip.slots[slot] = nil
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
	return InventoryService.getSnapshot(entityId)
end)

dispatcherAny:onRequest("InventoryAction", function(payload, _meta, context)
	local player = context.player
	if not player then
		return { ok = false, error = "no_player" }
	end
	local entityId = Registrar.getPlayerId(player)
	if not entityId then
		return { ok = false, error = "no_entity" }
	end
	local ok, err = handleAction(entityId, payload)
	return { ok = ok, error = err }
end)

-- Drop helper (stubbed world object representation)
function InventoryService.dropItem(entityId: string, uid: string, position: Vector3?): boolean
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
	spawnDrop(uid, position or Vector3.new(0, 3, 0), entityId)
	return true
end

return InventoryService
