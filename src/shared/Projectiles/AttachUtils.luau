--!strict
-- Shared helpers for resolving attachment targets for projectile spawns.

local AttachUtils = {}

local DEFAULT_PART = "RightHand"

function AttachUtils.resolveAttachPartName(model: Model?, preferred: string?): string
	local candidates = {}
	if preferred and preferred ~= "" then
		table.insert(candidates, preferred)
	end
	table.insert(candidates, "FX_Hand_R")
	table.insert(candidates, "RightHand")
	table.insert(candidates, "Right Arm")
	table.insert(candidates, "HumanoidRootPart")
	if model then
		for _, name in ipairs(candidates) do
			if model:FindFirstChild(name, true) then
				return name
			end
		end
	end
	return preferred or DEFAULT_PART
end

function AttachUtils.getAttachCFrame(model: Model?, partName: string): CFrame?
	if not model or not partName or partName == "" then
		return nil
	end
	local part = model:FindFirstChild(partName, true)
	if not part then
		return nil
	end
	if part:IsA("Attachment") then
		return part.WorldCFrame
	end
	if part:IsA("BasePart") then
		return part.CFrame
	end
	return nil
end

return AttachUtils
