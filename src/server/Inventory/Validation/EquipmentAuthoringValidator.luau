--!strict
-- Validates item/equipment authoring contracts during server startup.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Registry = require(ReplicatedStorage.Shared.items.Registry)
local VisualProfileRegistry = require(ReplicatedStorage.Shared.items.VisualProfileRegistry)
local EquipmentDefUtils = require(ReplicatedStorage.Shared.items.EquipmentDefUtils)
local RigSocketRegistry = require(ReplicatedStorage.Shared.items.RigSocketRegistry)
local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)

export type ValidationReport = {
	errors: { string },
	warnings: { string },
}

local EquipmentAuthoringValidator = {}

local function push(report: ValidationReport, severity: "error" | "warning", message: string)
	if severity == "error" then
		table.insert(report.errors, message)
	else
		table.insert(report.warnings, message)
	end
end

local function getItemAsset(assetName: string): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local items = assets and assets:FindFirstChild("Items")
	if not items then
		return nil
	end
	return items:FindFirstChild(assetName)
end

local function findAttachment(root: Instance, attachmentName: string): Attachment?
	for _, node in ipairs(root:GetDescendants()) do
		if node:IsA("Attachment") and node.Name == attachmentName then
			return node
		end
	end
	return nil
end

local function validateBinding(
	report: ValidationReport,
	scope: string,
	rigId: string,
	binding: ItemTypes.SocketedVisualBinding | ItemTypes.SegmentedVisualBinding
)
	local socket, canonicalName = RigSocketRegistry.getSocket(rigId, binding.characterSocket)
	if not socket or not canonicalName then
		push(report, "error", `{scope}: unknown character socket '{binding.characterSocket}' for rig '{rigId}'`)
	else
		if binding.characterSocket ~= canonicalName then
			push(
				report,
				"warning",
				`{scope}: uses legacy character socket alias '{binding.characterSocket}'; prefer canonical '{canonicalName}'`
			)
		end
	end

	local asset = getItemAsset(binding.asset)
	if not asset then
		push(report, "error", `{scope}: missing asset '{binding.asset}' in ReplicatedStorage.Assets.Items`)
		return
	end

	if binding.assetSocket and binding.assetSocket ~= "" and not findAttachment(asset, binding.assetSocket) then
		push(report, "error", `{scope}: asset '{binding.asset}' missing attachment '{binding.assetSocket}'`)
	end
end

local function validateProfile(report: ValidationReport, profile: ItemTypes.EquipmentVisualProfile)
	if not RigSocketRegistry.getProfile(profile.rig) then
		push(report, "error", `visual profile '{profile.id}': unknown rig '{profile.rig}'`)
		return
	end

	if profile.mode == "socketed" then
		if not profile.socketed and not profile.socketedSlots then
			push(report, "error", `visual profile '{profile.id}': socketed profile missing binding`)
			return
		end
		if profile.socketed then
			validateBinding(report, `visual profile '{profile.id}'`, profile.rig, profile.socketed)
		end
		if profile.socketedSlots then
			for slotName, binding in pairs(profile.socketedSlots) do
				validateBinding(report, `visual profile '{profile.id}' slot '{slotName}'`, profile.rig, binding)
			end
		end
		return
	end

	if profile.mode == "segmented" then
		local segments = profile.segments
		local segmentsBySlot = profile.segmentsBySlot
		if not segments and not segmentsBySlot then
			push(report, "error", `visual profile '{profile.id}': segmented profile missing segments`)
			return
		end
		if segments then
			for segmentName, binding in pairs(segments) do
				validateBinding(report, `visual profile '{profile.id}' segment '{segmentName}'`, profile.rig, binding)
			end
		end
		if segmentsBySlot then
			for slotName, slotSegments in pairs(segmentsBySlot) do
				for segmentName, binding in pairs(slotSegments) do
					validateBinding(
						report,
						`visual profile '{profile.id}' slot '{slotName}' segment '{segmentName}'`,
						profile.rig,
						binding
					)
				end
			end
		end
		return
	end

	if profile.mode == "skinned" then
		local binding = profile.skinned
		if not binding then
			push(report, "error", `visual profile '{profile.id}': skinned profile missing binding`)
			return
		end
		local asset = getItemAsset(binding.asset)
		if not asset then
			push(report, "error", `visual profile '{profile.id}': missing skinned asset '{binding.asset}'`)
		end
		if binding.anchorSocket and binding.anchorSocket ~= "" then
			local socket, canonicalName = RigSocketRegistry.getSocket(profile.rig, binding.anchorSocket)
			if not socket or not canonicalName then
				push(report, "error", `visual profile '{profile.id}': unknown anchor socket '{binding.anchorSocket}'`)
			elseif binding.anchorSocket ~= canonicalName then
				push(
					report,
					"warning",
					`visual profile '{profile.id}': uses legacy anchor socket alias '{binding.anchorSocket}'; prefer '{canonicalName}'`
				)
			end
		end
	end
end

local function validateDef(report: ValidationReport, def: ItemTypes.ItemDef)
	if not EquipmentDefUtils.isEquipment(def) then
		return
	end

	if not def.equipment then
		push(report, "warning", `item '{def.id}': still relies on legacy equipment fields only`)
		return
	end

	if not def.equipment.class or def.equipment.class == "" then
		push(report, "error", `item '{def.id}': equipment.class is required`)
	end

	if not def.equipment.slots or #def.equipment.slots == 0 then
		push(report, "error", `item '{def.id}': equipment.slots must contain at least one slot`)
	end

	if type(def.equipment.itemLevel) ~= "number" or def.equipment.itemLevel < 1 then
		push(report, "error", `item '{def.id}': equipment.itemLevel must be a positive number`)
	end

	if def.equipment.baseRolls then
		for _, roll in ipairs(def.equipment.baseRolls) do
			if roll.min > roll.max then
				push(report, "error", `item '{def.id}': base roll '{roll.target}' has min > max`)
			end
		end
	end

	if def.equipment.visualProfileId then
		if not VisualProfileRegistry.get(def.equipment.visualProfileId) then
			push(report, "error", `item '{def.id}': missing visual profile '{def.equipment.visualProfileId}'`)
		end
	end

	if def.equipment and (def.equipSlots or def.baseStats or def.requirements or def.visuals) then
		push(report, "warning", `item '{def.id}': still carries legacy equipment fields during migration`)
	end
end

function EquipmentAuthoringValidator.validateAll(): ValidationReport
	local report: ValidationReport = {
		errors = {},
		warnings = {},
	}

	for _, def in ipairs(Registry.list()) do
		validateDef(report, def)
	end

	for _, profile in ipairs(VisualProfileRegistry.list()) do
		validateProfile(report, profile)
	end

	return report
end

return EquipmentAuthoringValidator
