--!strict
-- Equipment panel slot binding + rendering runtime.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)
local EquipmentSlotSchema = require(ReplicatedStorage.Shared.ui.EquipmentSlotSchema)
local SlotVisuals = require(script.Parent.SlotVisuals)

type SlotNodes = SlotVisuals.SlotNodes

type SlotDiscoveryReport = {
	found: { [string]: Frame },
	duplicates: { [string]: { Frame } },
	missing: { string },
}

local EquipmentPanelRuntime = {}
EquipmentPanelRuntime.__index = EquipmentPanelRuntime

local function makeSlotLookup(slotIds: { string }): { [string]: string }
	local lookup: { [string]: string } = {}
	for _, id in ipairs(slotIds) do
		local canonical = EquipmentSlotSchema.canonicalize(id)
		if canonical then
			lookup[canonical] = canonical
		end
	end
	return lookup
end

local function discoverSlots(root: Instance, expectedSlots: { string }): SlotDiscoveryReport
	local found: { [string]: Frame } = {}
	local duplicates: { [string]: { Frame } } = {}
	local lookup = makeSlotLookup(expectedSlots)
	for _, node in ipairs(root:GetDescendants()) do
		if node:IsA("Frame") then
			local attr = node:GetAttribute("EquipmentSlot")
			if type(attr) == "string" then
				local canonical = EquipmentSlotSchema.canonicalize(attr)
				if canonical and lookup[canonical] then
					if not found[canonical] then
						found[canonical] = node
					else
						local bucket = duplicates[canonical]
						if not bucket then
							bucket = { found[canonical] }
							duplicates[canonical] = bucket
						end
						table.insert(bucket, node)
					end
				end
			end
		end
	end
	local missing = {}
	for canonical in pairs(lookup) do
		if not found[canonical] then
			table.insert(missing, canonical)
		end
	end
	table.sort(missing)
	return { found = found, duplicates = duplicates, missing = missing }
end

local function formatBindingReport(report: SlotDiscoveryReport): string
	local foundNames = {}
	for slotId, frame in pairs(report.found) do
		table.insert(foundNames, `{slotId}=>{frame:GetFullName()}`)
	end
	table.sort(foundNames)

	local duplicateNames = {}
	for slotId, frames in pairs(report.duplicates) do
		local paths = {}
		for _, frame in ipairs(frames) do
			table.insert(paths, frame:GetFullName())
		end
		table.sort(paths)
		table.insert(duplicateNames, `{slotId}=>[{table.concat(paths, ", ")}]`)
	end
	table.sort(duplicateNames)

	local lines = {
		`EquipmentPanelRuntime: slot binding report`,
		`  found: {#foundNames}`,
	}
	if #foundNames > 0 then
		table.insert(lines, `  mappings: {table.concat(foundNames, "; ")}`)
	end
	if #report.missing > 0 then
		table.insert(lines, `  missing: {table.concat(report.missing, ", ")}`)
	end
	if #duplicateNames > 0 then
		table.insert(lines, `  duplicates: {table.concat(duplicateNames, "; ")}`)
	end
	return table.concat(lines, "\n")
end

local function connectSlotClick(slotFrame: Frame, nodes: SlotNodes, handler: () -> ())
	if nodes.button then
		nodes.button.MouseButton1Click:Connect(handler)
		return
	end

	slotFrame.Active = true
	slotFrame.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			handler()
		end
	end)
end

function EquipmentPanelRuntime.new(panelPart: BasePart, reporter: ((string) -> ())?): any
	local self = setmetatable({}, EquipmentPanelRuntime)
	self._panelPart = panelPart
	self._slots = {}
	self._slotNodes = {}
	self._reported = false
	self._reporter = reporter
	self._inspectSelectionHandler = nil :: ((string?) -> ())?
	self._selectedUid = nil :: string?
	return self
end

function EquipmentPanelRuntime:_emitReport(report: SlotDiscoveryReport)
	if self._reported then
		return
	end
	if self._reporter then
		self._reporter(formatBindingReport(report))
	end
	self._reported = true
end

function EquipmentPanelRuntime:_bind(expectedSlots: { string })
	local report = discoverSlots(self._panelPart, expectedSlots)
	self._slots = report.found
	self._slotNodes = {}
	for slotId, slotFrame in pairs(self._slots) do
		local nodes = SlotVisuals.bind(slotFrame)
		self._slotNodes[slotId] = nodes
		SlotVisuals.setEmpty(slotFrame, nodes)
		connectSlotClick(slotFrame, nodes, function()
			self:_emitSelectionForSlot(slotFrame)
		end)
	end
	self:_emitReport(report)
end

function EquipmentPanelRuntime:_bindDefaultSlots()
	self:_bind(EquipmentSlotSchema.list())
end

function EquipmentPanelRuntime:_ensureBound()
	if next(self._slots) == nil then
		self:_bindDefaultSlots()
	end
end

function EquipmentPanelRuntime:_refreshSelection(selectedUid: string?)
	for _, slotFrame in pairs(self._slots) do
		local isSelected = selectedUid ~= nil and slotFrame:GetAttribute("ItemUid") == selectedUid
		local selectionFrame = slotFrame:FindFirstChild("SelectionFrame", true)
		if selectionFrame and selectionFrame:IsA("GuiObject") then
			selectionFrame.Visible = isSelected
		end
	end
end

function EquipmentPanelRuntime:setSelectedUid(uid: string?)
	self._selectedUid = uid
	self:_refreshSelection(uid)
end

function EquipmentPanelRuntime:clearSelection()
	self:setSelectedUid(nil)
end

function EquipmentPanelRuntime:_emitSelectionForSlot(slotFrame: Frame)
	local uid = slotFrame:GetAttribute("ItemUid")
	local selectedUid = if type(uid) == "string" then uid else nil
	self:setSelectedUid(selectedUid)
	if self._inspectSelectionHandler then
		self._inspectSelectionHandler(selectedUid)
	end
end

function EquipmentPanelRuntime:setInspectSelectionHandler(handler: ((string?) -> ())?)
	self._inspectSelectionHandler = handler
end

function EquipmentPanelRuntime:refresh(
	equip: ItemTypes.EquipmentState?,
	items: { [string]: ItemTypes.ItemInstance },
	registryGet: (itemId: string) -> ItemTypes.ItemDef?
)
	if not equip then
		return
	end
	self:_ensureBound()
	for slotName, slotFrame in pairs(self._slots) do
		local nodes = self._slotNodes[slotName]
		if nodes then
			local uid = equip.slots[slotName]
			if uid then
				local item = items[uid]
				local def = item and registryGet(item.itemId)
				if item and def then
					SlotVisuals.setItem(slotFrame, item, def, nodes)
				else
					SlotVisuals.setEmpty(slotFrame, nodes)
				end
			else
				SlotVisuals.setEmpty(slotFrame, nodes)
			end
		end
	end
	self:_refreshSelection(self._selectedUid)
end

return EquipmentPanelRuntime
