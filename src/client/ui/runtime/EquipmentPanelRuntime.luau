--!strict
-- Equipment panel slot binding + rendering runtime.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryClient = require(script.Parent.Parent.Parent.Inventory.InventoryClient)
local EquipmentDefUtils = require(ReplicatedStorage.Shared.items.EquipmentDefUtils)
local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)
local EquipmentSlotSchema = require(ReplicatedStorage.Shared.ui.EquipmentSlotSchema)
local PanelBinder = require(script.Parent.PanelBinder)
local SlotVisuals = require(script.Parent.SlotVisuals)

type SlotNodes = SlotVisuals.SlotNodes

type SlotDiscoveryReport = {
	found: { [string]: Frame },
	duplicates: { [string]: { Frame } },
	missing: { string },
}

local EquipmentPanelRuntime = {}
EquipmentPanelRuntime.__index = EquipmentPanelRuntime

local CANDIDATE_GRID_NAME = "InventoryGrid"
local CANDIDATE_TEMPLATE_NAME = "ItemSlotTemplate"

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

	local lastClickTime = 0
	local function onInput(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end

		local now = os.clock()
		if now - lastClickTime < 0.05 then
			return
		end
		lastClickTime = now
		handler()
	end

	local clickTargets: { GuiObject } = { slotFrame }
	for _, descendant in ipairs(slotFrame:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			table.insert(clickTargets, descendant)
		end
	end

	for _, target in ipairs(clickTargets) do
		target.Active = true
		target.InputBegan:Connect(onInput)
	end
end

local function getCompatibleSocketIds(def: ItemTypes.ItemDef): { string }
	local compatible = {}
	if not EquipmentDefUtils.isEquipment(def) then
		return compatible
	end

	local equipSlots = EquipmentDefUtils.getEquipSlots(def)
	if not equipSlots then
		return compatible
	end

	local validSockets = makeSlotLookup(EquipmentSlotSchema.list())
	for _, rawSlot in ipairs(equipSlots) do
		local canonical = EquipmentSlotSchema.canonicalize(rawSlot)
		if canonical and validSockets[canonical] then
			table.insert(compatible, canonical)
		end
	end

	return compatible
end

local function hasSocketId(socketIds: { string }, slotId: string): boolean
	for _, socketId in ipairs(socketIds) do
		if socketId == slotId then
			return true
		end
	end
	return false
end

local function resolveCandidateTargetSlot(def: ItemTypes.ItemDef, selectedSlotId: string?): string?
	local compatible = getCompatibleSocketIds(def)
	if #compatible == 0 then
		return nil
	end

	if selectedSlotId and hasSocketId(compatible, selectedSlotId) then
		return selectedSlotId
	end

	return compatible[1]
end

local function resolveSlotId(slotFrame: Frame): string?
	local attr = slotFrame:GetAttribute("EquipmentSlot")
	if type(attr) ~= "string" then
		return nil
	end
	return EquipmentSlotSchema.canonicalize(attr)
end

function EquipmentPanelRuntime.new(panelPart: BasePart, reporter: ((string) -> ())?): any
	local self = setmetatable({}, EquipmentPanelRuntime)
	self._panelPart = panelPart
	self._slots = {}
	self._slotNodes = {}
	self._candidateGrid = nil :: ScrollingFrame?
	self._candidateTemplate = nil :: Frame?
	self._candidateSlots = {} :: { Frame }
	self._lastInventory = nil :: ItemTypes.InventoryState?
	self._lastItems = nil :: { [string]: ItemTypes.ItemInstance }?
	self._lastRegistryGet = nil :: ((itemId: string) -> ItemTypes.ItemDef?)?
	self._reported = false
	self._reporter = reporter
	self._inspectSelectionHandler = nil :: ((string?) -> ())?
	self._selectedUid = nil :: string?
	self._selectedSlotId = nil :: string?
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

function EquipmentPanelRuntime:_bindCandidateGrid()
	if self._candidateGrid ~= nil or self._candidateTemplate ~= nil then
		return
	end

	local binder = PanelBinder.new(self._panelPart)
	local grid = binder:find({ CANDIDATE_GRID_NAME }, "ScrollingFrame") :: ScrollingFrame?
	if not grid then
		return
	end

	local template = PanelBinder.new(grid):find({ CANDIDATE_TEMPLATE_NAME }, "Frame") :: Frame?
	if not template then
		warn(`EquipmentPanelRuntime: missing {CANDIDATE_GRID_NAME}.{CANDIDATE_TEMPLATE_NAME}`)
		return
	end

	template.Visible = false
	self._candidateGrid = grid
	self._candidateTemplate = template
end

function EquipmentPanelRuntime:_ensureBound()
	if next(self._slots) == nil then
		self:_bindDefaultSlots()
	end
	self:_bindCandidateGrid()
end

function EquipmentPanelRuntime:_clearCandidateSlots()
	for _, slotFrame in ipairs(self._candidateSlots) do
		slotFrame:Destroy()
	end
	table.clear(self._candidateSlots)
end

function EquipmentPanelRuntime:_refreshSelection(selectedUid: string?)
	for slotId, slotFrame in pairs(self._slots) do
		local isSelected = self._selectedSlotId == slotId
			or (selectedUid ~= nil and slotFrame:GetAttribute("ItemUid") == selectedUid)
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
	self._selectedSlotId = nil
	self:setSelectedUid(nil)
	self:_rerenderCandidateItems()
end

function EquipmentPanelRuntime:_emitSelectionForSlot(slotFrame: Frame)
	self._selectedSlotId = resolveSlotId(slotFrame)
	local uid = slotFrame:GetAttribute("ItemUid")
	local selectedUid = if type(uid) == "string" then uid else nil
	self:setSelectedUid(selectedUid)
	self:_rerenderCandidateItems()
	if self._inspectSelectionHandler then
		self._inspectSelectionHandler(selectedUid)
	end
end

function EquipmentPanelRuntime:setInspectSelectionHandler(handler: ((string?) -> ())?)
	self._inspectSelectionHandler = handler
end

function EquipmentPanelRuntime:_renderCandidateItems(
	inventory: ItemTypes.InventoryState?,
	items: { [string]: ItemTypes.ItemInstance },
	registryGet: (itemId: string) -> ItemTypes.ItemDef?
)
	self:_clearCandidateSlots()

	local slotId = self._selectedSlotId
	local grid = self._candidateGrid
	local template = self._candidateTemplate
	if not inventory or not grid or not template then
		return
	end

	local layoutOrder = 0
	for slotIndex = 1, inventory.capacity do
		local uid = inventory.slots[slotIndex]
		local item = if uid then items[uid] else nil
		local def = if item then registryGet(item.itemId) else nil
		local targetSlotId = if def then resolveCandidateTargetSlot(def, slotId) else nil
		if item and def and targetSlotId then
			layoutOrder += 1
			local clone = template:Clone()
			clone.Name = `Candidate_{slotIndex}`
			clone.LayoutOrder = layoutOrder
			clone.Visible = true
			clone.Parent = grid
			local selectionFrame = clone:FindFirstChild("SelectionFrame", true)
			if selectionFrame and selectionFrame:IsA("GuiObject") then
				selectionFrame.Visible = false
			end

			local nodes = SlotVisuals.bind(clone)
			SlotVisuals.setItem(clone, item, def, nodes)
			connectSlotClick(clone, nodes, function()
				self:setSelectedUid(item.uid)
				if self._inspectSelectionHandler then
					self._inspectSelectionHandler(item.uid)
				end
				InventoryClient.requestAction({
					action = "equip",
					fromSlot = slotIndex,
					toSlot = targetSlotId,
				})
			end)

			table.insert(self._candidateSlots, clone)
		end
	end
end

function EquipmentPanelRuntime:_rerenderCandidateItems()
	if not self._lastItems or not self._lastRegistryGet then
		return
	end
	self:_renderCandidateItems(self._lastInventory, self._lastItems, self._lastRegistryGet)
end

function EquipmentPanelRuntime:refresh(
	equip: ItemTypes.EquipmentState?,
	inventory: ItemTypes.InventoryState?,
	items: { [string]: ItemTypes.ItemInstance },
	registryGet: (itemId: string) -> ItemTypes.ItemDef?
)
	if not equip then
		return
	end
	self._lastInventory = inventory
	self._lastItems = items
	self._lastRegistryGet = registryGet
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
	self:_renderCandidateItems(inventory, items, registryGet)
end

return EquipmentPanelRuntime
