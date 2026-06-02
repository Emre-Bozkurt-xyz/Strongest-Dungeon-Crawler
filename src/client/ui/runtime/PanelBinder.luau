--!strict

local PanelBinder = {}
PanelBinder.__index = PanelBinder

export type PanelBinderType = {
	_root: Instance,
	_byName: { [string]: { Instance } },
	find: (self: PanelBinderType, names: { string }, className: string?) -> Instance?,
	require: (self: PanelBinderType, names: { string }, className: string, context: string) -> Instance,
}

local function indexDescendants(root: Instance): { [string]: { Instance } }
	local byName: { [string]: { Instance } } = {}
	for _, node in ipairs(root:GetDescendants()) do
		local bucket = byName[node.Name]
		if not bucket then
			bucket = {}
			byName[node.Name] = bucket
		end
		table.insert(bucket, node)
	end
	return byName
end

function PanelBinder.new(root: Instance): PanelBinderType
	local self = setmetatable({}, PanelBinder) :: any
	self._root = root
	self._byName = indexDescendants(root)
	return self :: any
end

function PanelBinder:find(names: { string }, className: string?): Instance?
	for _, name in ipairs(names) do
		local bucket = self._byName[name]
		if bucket then
			if not className then
				return bucket[1]
			end
			for _, node in ipairs(bucket) do
				if node:IsA(className) then
					return node
				end
			end
		end
	end
	return nil
end

function PanelBinder:require(names: { string }, className: string, context: string): Instance
	local node = self:find(names, className)
	assert(node, `PanelBinder: missing {context} ({className})`)
	return node
end

return PanelBinder
