--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PanelTemplateSchema = require(ReplicatedStorage.Shared.ui.PanelTemplateSchema)
local PanelBinder = require(script.Parent.PanelBinder)

local PanelTemplateResolver = {}
local RESOLVE_TIMEOUT_SECONDS = 2

local function findByPath(root: Instance, segments: { string }): Instance?
	local node: Instance? = root
	for _, segment in ipairs(segments) do
		if not node then
			return nil
		end
		node = node:FindFirstChild(segment) or node:WaitForChild(segment, RESOLVE_TIMEOUT_SECONDS)
	end
	return node
end

function PanelTemplateResolver.resolveWorldPart(panelId: string): BasePart?
	local schema = PanelTemplateSchema.get(panelId)
	if not schema then
		warn(`PanelTemplateResolver: unknown panel schema '{panelId}'`)
		return nil
	end

	local container = findByPath(ReplicatedStorage, schema.templatePath)
	if not container then
		warn(`PanelTemplateResolver: missing template container for panel '{panelId}'`)
		return nil
	end

	local binder = PanelBinder.new(container)
	for _, reqNode in ipairs(schema.requiredNodes) do
		if reqNode.required then
			local node = binder:find({ reqNode.name }, reqNode.className)
			if not node then
				local namedNode = binder:find({ reqNode.name })
				if namedNode then
					warn(
						`PanelTemplateResolver: required node '{reqNode.name}' for panel '{panelId}' exists but has class '{namedNode.ClassName}' (expected '{reqNode.className}')`
					)
				end
				warn(
					`PanelTemplateResolver: missing required node '{reqNode.name}:{reqNode.className}' for panel '{panelId}'`
				)
				return nil
			end
		end
	end

	local worldPart = container:FindFirstChild("WorldPart") or container:WaitForChild("WorldPart", RESOLVE_TIMEOUT_SECONDS)
	if worldPart and worldPart:IsA("BasePart") then
		return worldPart
	end
	warn(`PanelTemplateResolver: missing WorldPart for panel '{panelId}'`)
	return nil
end

return PanelTemplateResolver
