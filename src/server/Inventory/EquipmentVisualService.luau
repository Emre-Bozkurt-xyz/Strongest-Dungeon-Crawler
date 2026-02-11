--!strict
-- EquipmentVisualService: attaches item visuals to characters when equipped.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Registrar = require(ServerScriptService.Server.Services.Registrar)
local Registry = require(ReplicatedStorage.Shared.items.Registry)
local ItemInstances = require(script.Parent.ItemInstances)
local EquipmentService = require(script.Parent.EquipmentService)

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

local function attachVisual(entity: Model, slot: string, uid: string)
	local inst = ItemInstances.get(uid)
	if not inst then
		return
	end
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
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local itemFolder = assets and assets:FindFirstChild("Items")
	local template = itemFolder and itemFolder:FindFirstChild(spec.model)
	if not template then
		warn(`EquipmentVisualService: missing model {spec.model}`)
		return
	end
	local clone = template:Clone()
	local primary = getPrimaryPart(clone)
	if not primary then
		clone:Destroy()
		return
	end
	primary.Anchored = false
	primary.CanCollide = false

	local attachTarget = entity:FindFirstChild(attachName, true)
	if not attachTarget then
		warn(`EquipmentVisualService: attach target {attachName} not found`)
		clone:Destroy()
		return
	end
	local attachPart: BasePart?
	local attachCFrame: CFrame
	if attachTarget:IsA("Attachment") then
		attachPart = attachTarget.Parent :: BasePart?
		attachCFrame = attachTarget.WorldCFrame
	else
		attachPart = attachTarget :: BasePart?
		attachCFrame = attachPart and attachPart.CFrame or entity:GetPivot()
	end
	if not attachPart then
		clone:Destroy()
		return
	end

	local offset = spec.offset or CFrame.new()
	local itemAttachLocal: CFrame? = nil
	if spec.itemAttach then
		itemAttachLocal = resolveItemAttachLocal(clone, spec.itemAttach)
		if not itemAttachLocal then
			warn(`EquipmentVisualService: item attach {spec.itemAttach} not found in {spec.model}`)
			clone:Destroy()
			return
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

	local entityId = Registrar.getEntityId(entity)
	if not entityId then
		clone:Destroy()
		return
	end
	clone.Parent = entity
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

function EquipmentVisualService.start()
	EquipmentService.onSlotChanged(onSlotChanged)
end

return EquipmentVisualService
