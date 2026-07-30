--!strict
-- EquipmentVisualService: attaches item visuals to characters when equipped.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Registrar = require(ServerScriptService.Server.Services.Registrar)
local Registry = require(ReplicatedStorage.Shared.items.Registry)
local EquipmentDefUtils = require(ReplicatedStorage.Shared.items.EquipmentDefUtils)
local VisualProfileRegistry = require(ReplicatedStorage.Shared.items.VisualProfileRegistry)
local RigSocketRegistry = require(ReplicatedStorage.Shared.items.RigSocketRegistry)
local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)
local ItemInstances = require(script.Parent.ItemInstances)
local EquipmentRepository = require(script.Parent.Domain.EquipmentRepository)

local EquipmentVisualService = {}

local visualsByEntity: { [string]: { [string]: Instance } } = {}

local function getPrimaryPart(inst: Instance): BasePart?
	if inst:IsA("BasePart") then
		return inst
	end
	if inst:IsA("Model") then
		local handle = inst:FindFirstChild("Handle", true)
		if handle and handle:IsA("BasePart") then
			inst.PrimaryPart = handle
			return handle
		end
		if inst.PrimaryPart then
			return inst.PrimaryPart
		end
		local part = inst:FindFirstChildWhichIsA("BasePart", true)
		if part then
			inst.PrimaryPart = part
		end
		return part
	end
	return nil
end

local function getAllParts(inst: Instance): { BasePart }
	local parts = {}
	if inst:IsA("BasePart") then
		table.insert(parts, inst)
		return parts
	end
	if inst:IsA("Model") then
		for _, node in ipairs(inst:GetDescendants()) do
			if node:IsA("BasePart") then
				table.insert(parts, node)
			end
		end
	end
	return parts
end

local function prepVisualParts(parts: { BasePart })
	for _, part in ipairs(parts) do
		part.Anchored = false
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
	end
end

local function weldPartsToPrimary(parts: { BasePart }, primary: BasePart)
	for _, part in ipairs(parts) do
		if part ~= primary then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = primary
			weld.Part1 = part
			weld.Parent = primary
		end
	end
end

local function resolveItemAttachLocal(inst: Instance, itemAttach: string): CFrame?
	local attach = inst:FindFirstChild(itemAttach, true)
	if not attach or not attach:IsA("Attachment") then
		return nil
	end
	if inst:IsA("Model") then
		return inst:GetPivot():ToObjectSpace(attach.WorldCFrame)
	end
	if inst:IsA("BasePart") then
		return (inst :: BasePart).CFrame:ToObjectSpace(attach.WorldCFrame)
	end
	return nil
end

local function resolveAssetTemplate(assetName: string): Instance?
	if assetName == "" then
		return nil
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local itemFolder = assets and assets:FindFirstChild("Items")
	return if itemFolder then itemFolder:FindFirstChild(assetName) else nil
end

local function findDescendantAttachment(root: Instance, names: { string }): Attachment?
	for _, node in ipairs(root:GetDescendants()) do
		if node:IsA("Attachment") then
			for _, name in ipairs(names) do
				if node.Name == name then
					return node
				end
			end
		end
	end
	return nil
end

local function findDescendantPart(root: Instance, names: { string }): BasePart?
	for _, node in ipairs(root:GetDescendants()) do
		if node:IsA("BasePart") then
			for _, name in ipairs(names) do
				if node.Name == name then
					return node
				end
			end
		end
	end
	return nil
end

local function resolveSocket(entity: Model, rigId: string?, socketName: string): (BasePart?, CFrame?)
	local searchNames = if rigId then RigSocketRegistry.getSearchNames(rigId, socketName) else { socketName }

	local attach = findDescendantAttachment(entity, searchNames)
	if attach then
		local parent = attach.Parent
		if parent and parent:IsA("BasePart") then
			return parent, attach.WorldCFrame
		end
		return nil, nil
	end

	local part = findDescendantPart(entity, searchNames)
	if part then
		return part, part.CFrame
	end

	return nil, nil
end

local function buildSocketedVisual(
	entity: Model,
	rigId: string?,
	binding: ItemTypes.SocketedVisualBinding,
	parent: Instance
): Instance?
	local template = resolveAssetTemplate(binding.asset)
	if not template then
		warn(`EquipmentVisualService: missing asset {binding.asset}`)
		return nil
	end

	local clone = template:Clone()
	local primary = getPrimaryPart(clone)
	if not primary then
		clone:Destroy()
		return nil
	end

	local visualParts = getAllParts(clone)
	prepVisualParts(visualParts)

	local attachPart, attachCFrame = resolveSocket(entity, rigId, binding.characterSocket)
	if not attachPart or not attachCFrame then
		local describedSocket = if rigId
			then RigSocketRegistry.describeSocket(rigId, binding.characterSocket)
			else binding.characterSocket
		warn(`EquipmentVisualService: character socket {describedSocket} not found`)
		clone:Destroy()
		return nil
	end

	local offset = binding.offset or CFrame.new()
	local itemAttachLocal: CFrame? = nil
	if binding.assetSocket and binding.assetSocket ~= "" then
		itemAttachLocal = resolveItemAttachLocal(clone, binding.assetSocket)
		if not itemAttachLocal then
			warn(`EquipmentVisualService: asset socket {binding.assetSocket} not found in {binding.asset}`)
			clone:Destroy()
			return nil
		end
	end

	local targetCFrame = attachCFrame * offset
	if itemAttachLocal then
		targetCFrame = targetCFrame * itemAttachLocal:Inverse()
	end

	if clone:IsA("Model") then
		clone:PivotTo(targetCFrame)
	else
		(primary :: BasePart).CFrame = targetCFrame
	end

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = primary
	weld.Part1 = attachPart
	weld.Parent = primary
	weldPartsToPrimary(visualParts, primary)

	clone.Parent = parent
	return clone
end

local function clearVisual(entityId: string, slot: string)
	local bucket = visualsByEntity[entityId]
	if not bucket then
		return
	end
	local inst = bucket[slot]
	if inst then
		inst:Destroy()
		bucket[slot] = nil
	end
end

local function resolveVisualSpec(itemId: string, slot: string)
	local def = Registry.get(itemId)
	if not def or not def.visuals then
		return nil
	end
	return def.visuals[slot] or def.visuals["default"]
end

local function resolveSocketedBinding(
	profile: ItemTypes.EquipmentVisualProfile,
	slot: string
): ItemTypes.SocketedVisualBinding?
	if profile.socketedSlots then
		return profile.socketedSlots[slot] or profile.socketed
	end
	return profile.socketed
end

local function resolveSegmentBindings(
	profile: ItemTypes.EquipmentVisualProfile,
	slot: string
): { [string]: ItemTypes.SegmentedVisualBinding }?
	if profile.segmentsBySlot then
		return profile.segmentsBySlot[slot] or profile.segments
	end
	return profile.segments
end

local function attachFromProfile(entity: Model, slot: string, profile: ItemTypes.EquipmentVisualProfile): Instance?
	if profile.mode == "socketed" then
		local binding = resolveSocketedBinding(profile, slot)
		if not binding then
			return nil
		end
		return buildSocketedVisual(entity, profile.rig, binding, entity)
	end

	if profile.mode == "segmented" then
		local bindings = resolveSegmentBindings(profile, slot)
		if not bindings then
			return nil
		end
		local folder = Instance.new("Folder")
		folder.Name = `EquipmentVisual_{slot}`
		local builtCount = 0
		for segmentName, binding in pairs(bindings) do
			local clone = buildSocketedVisual(entity, profile.rig, binding, folder)
			if clone then
				clone.Name = segmentName
				builtCount += 1
			end
		end
		if builtCount == 0 then
			folder:Destroy()
			return nil
		end
		folder.Parent = entity
		return folder
	end

	if profile.mode == "skinned" then
		warn(`EquipmentVisualService: skinned visual profiles are not implemented yet ({profile.id})`)
	end

	return nil
end

local function attachVisual(entity: Model, slot: string, uid: string)
	local inst = ItemInstances.get(uid)
	if not inst then
		return
	end
	local def = Registry.get(inst.itemId)
	if not def then
		return
	end

	local clone: Instance? = nil
	local profileId = EquipmentDefUtils.getVisualProfileId(def)
	if profileId then
		local profile = VisualProfileRegistry.get(profileId)
		if not profile then
			warn(`EquipmentVisualService: missing visual profile {profileId}`)
		else
			clone = attachFromProfile(entity, slot, profile)
		end
	end

	if not clone then
		local spec = resolveVisualSpec(inst.itemId, slot)
		if not spec then
			return
		end
		if type(spec.model) ~= "string" or spec.model == "" then
			return
		end
		local attachName = spec.attach
		if type(attachName) ~= "string" or attachName == "" then
			return
		end
		clone = buildSocketedVisual(entity, nil, {
			asset = spec.model,
			characterSocket = attachName,
			assetSocket = spec.itemAttach,
			offset = spec.offset,
		}, entity)
	end

	if not clone then
		return
	end

	local entityId = Registrar.getEntityId(entity)
	if not entityId then
		clone:Destroy()
		return
	end
	visualsByEntity[entityId] = visualsByEntity[entityId] or {}
	visualsByEntity[entityId][slot] = clone
end

local function onSlotChanged(entityId: string, slot: string, uid: string?)
	clearVisual(entityId, slot)
	if not uid then
		return
	end
	local entity = Registrar.getEntityById(entityId)
	if not entity then
		return
	end
	attachVisual(entity, slot, uid)
end

-- The live attached visual for a slot, or nil when the slot is empty or its asset failed to build.
-- Callers may read the returned instance but must not reparent or destroy it; clearVisual owns its
-- lifetime.
function EquipmentVisualService.getVisual(entityId: string, slot: string): Instance?
	local bucket = visualsByEntity[entityId]
	if not bucket then
		return nil
	end
	local inst = bucket[slot]
	if inst and inst.Parent then
		return inst
	end
	return nil
end

-- World CFrame of a named Attachment on the visual equipped in `slot`.
function EquipmentVisualService.getSocketCFrame(entityId: string, slot: string, socketName: string): CFrame?
	if socketName == "" then
		return nil
	end
	local visual = EquipmentVisualService.getVisual(entityId, slot)
	if not visual then
		return nil
	end
	local node = visual:FindFirstChild(socketName, true)
	if node and node:IsA("Attachment") then
		return node.WorldCFrame
	end
	return nil
end

function EquipmentVisualService.start()
	EquipmentRepository.onSlotChanged(onSlotChanged)
end

return EquipmentVisualService
