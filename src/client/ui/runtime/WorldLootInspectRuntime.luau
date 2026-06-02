--!strict
-- Owns the world-space nearby loot panel: row rendering, selection highlight, and anchoring near loot.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldGUIManager = require(script.Parent.Parent.Parent.WorldGUIManager)
local SharedConfig = require(ReplicatedStorage.Shared.Config)
local Registry = require(ReplicatedStorage.Shared.items.Registry)
local DevTuningService = require(script.Parent.Parent.Parent.dev.DevTuningService)
local PanelBinder = require(script.Parent.PanelBinder)
local PanelTemplateResolver = require(script.Parent.PanelTemplateResolver)

local WorldLootInspectRuntime = {}
WorldLootInspectRuntime.__index = WorldLootInspectRuntime

export type LootEntry = {
	uid: string,
	itemId: string,
	displayName: string,
	rarity: string?,
	stackSize: number?,
	part: BasePart,
	distance: number,
}

export type Config = {
	groupName: string,
	offset: Vector3,
	lerpSpeed: number,
	maxRadius: number,
	maxVisibleRows: number,
	hintText: string,
}

type Callbacks = {
	onSelect: ((number, LootEntry) -> ())?,
	onPickup: ((number, LootEntry) -> ())?,
}

type RowRuntime = {
	root: Frame,
	icon: ImageLabel?,
	nameLabel: TextLabel?,
	stackLabel: TextLabel?,
	hintLabel: TextLabel?,
	pickupButton: GuiButton?,
	selectionFrame: GuiObject?,
	rarityFrame: GuiObject?,
}

local PANEL_NAME = "WorldLootInspectPanel"
local BASE_CONFIG = SharedConfig.WorldLootInspect

local RARITY_COLORS = {
	normal = Color3.fromRGB(200, 200, 200),
	magic = Color3.fromRGB(88, 152, 255),
	rare = Color3.fromRGB(255, 210, 90),
	unique = Color3.fromRGB(220, 140, 60),
}

local function tunedString(path: string, fallback: string): string
	local value = DevTuningService.get(path)
	return if type(value) == "string" then value else fallback
end

local function tunedNumber(path: string, fallback: number): number
	local value = DevTuningService.get(path)
	return if type(value) == "number" then value else fallback
end

local function tunedVector3(path: string, fallback: Vector3): Vector3
	local value = DevTuningService.get(path)
	return if typeof(value) == "Vector3" then value else fallback
end

local function setOptionalText(node: TextLabel?, text: string)
	if node then
		node.Text = text
	end
end

local function restoreOriginalVisualState(root: Instance)
	local function restoreNode(node: Instance)
		if node:IsA("GuiObject") then
			local originalBackgroundTransparency = node:GetAttribute("OriginalBackgroundTransparency")
			if type(originalBackgroundTransparency) == "number" then
				node.BackgroundTransparency = originalBackgroundTransparency
			end
		end

		if node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then
			local originalTextTransparency = node:GetAttribute("OriginalTextTransparency")
			if type(originalTextTransparency) == "number" then
				(node :: any).TextTransparency = originalTextTransparency
			end
			local originalTextStrokeTransparency = node:GetAttribute("OriginalTextStrokeTransparency")
			if type(originalTextStrokeTransparency) == "number" then
				(node :: any).TextStrokeTransparency = originalTextStrokeTransparency
			end
		end

		if node:IsA("ImageLabel") or node:IsA("ImageButton") then
			local originalImageTransparency = node:GetAttribute("OriginalImageTransparency")
			if type(originalImageTransparency) == "number" then
				(node :: any).ImageTransparency = originalImageTransparency
			end
		end

		if node:IsA("UIStroke") then
			local originalStrokeTransparency = node:GetAttribute("OriginalStrokeTransparency")
			if type(originalStrokeTransparency) == "number" then
				node.Transparency = originalStrokeTransparency
			end
		end
	end

	restoreNode(root)
	for _, child in ipairs(root:GetDescendants()) do
		restoreNode(child)
	end
end

local function applyRarityVisual(rarityNode: GuiObject?, rarity: string?)
	if not rarityNode then
		return
	end
	local color = RARITY_COLORS[rarity or "normal"] or RARITY_COLORS.normal
	rarityNode.Visible = rarity ~= nil
	if rarityNode:IsA("ImageLabel") then
		rarityNode.ImageColor3 = color
	else
		rarityNode.BackgroundColor3 = color
	end
end

function WorldLootInspectRuntime.new(config: Config)
	local self = setmetatable({}, WorldLootInspectRuntime)
	self._wgm = WorldGUIManager.getInstance()
	self._config = config
	self._panelPart = nil :: BasePart?
	self._root = nil :: Frame?
	self._titleLabel = nil :: TextLabel?
	self._hintLabel = nil :: TextLabel?
	self._listContainer = nil :: ScrollingFrame?
	self._rowTemplate = nil :: Frame?
	self._listLayout = nil :: UIListLayout?
	self._entries = {} :: { LootEntry }
	self._selectedIndex = 1
	self._callbacks = nil :: Callbacks?
	self._tuneConn = nil :: (() -> ())?
	self._rowsByUid = {} :: { [string]: RowRuntime }
	self._orderedUids = {} :: { string }
	self._entryByUid = {} :: { [string]: LootEntry }
	self._indexByUid = {} :: { [string]: number }
	self._visible = false
	self._followTarget = nil :: BasePart?

	local template = PanelTemplateResolver.resolveWorldPart(PANEL_NAME)
	if template then
		self._panelPart = template:Clone()
		self._panelPart.Parent = workspace

		self._wgm:registerPanel({
			name = PANEL_NAME,
			part = self._panelPart,
			group = config.groupName,
			faceCamera = true,
			faceMode = "camera",
			followMode = "target",
			followTarget = nil,
			offset = config.offset,
			maxRadius = config.maxRadius,
			lerpSpeed = config.lerpSpeed,
		})
		self._wgm:setPanelVisibility(PANEL_NAME, false, 0, workspace)

		local binder = PanelBinder.new(self._panelPart)
		self._root = binder:find({ "Root" }, "Frame") :: Frame?
		self._titleLabel = binder:find({ "TitleLabel" }, "TextLabel") :: TextLabel?
		self._hintLabel = binder:find({ "HintLabel" }, "TextLabel") :: TextLabel?
		self._listContainer = binder:find({ "LootContainer" }, "ScrollingFrame") :: ScrollingFrame?
		if self._listContainer then
			local listBinder = PanelBinder.new(self._listContainer)
			self._rowTemplate = listBinder:find({ "RowTemplate" }, "Frame") :: Frame?
			self._listLayout = listBinder:find({ "UIListLayout" }, "UIListLayout") :: UIListLayout?
			if self._rowTemplate then
				self._rowTemplate.Visible = false
			end
		end
	end

	self._tuneConn = DevTuningService.subscribe("WorldLootInspect", function()
		self:_applyConfigTuning()
		self:refresh()
	end)
	self:_applyConfigTuning()

	return self
end

function WorldLootInspectRuntime:isAvailable(): boolean
	return self._panelPart ~= nil and self._listContainer ~= nil and self._rowTemplate ~= nil
end

function WorldLootInspectRuntime:_applyConfigTuning()
	if not self._panelPart then
		return
	end

	self._config.groupName = tunedString("WorldLootInspect.groupName", BASE_CONFIG.groupName)
	self._config.offset = tunedVector3("WorldLootInspect.panel.offset", BASE_CONFIG.panel.offset)
	self._config.lerpSpeed = tunedNumber("WorldLootInspect.panel.lerpSpeed", BASE_CONFIG.panel.lerpSpeed)
	self._config.maxRadius = tunedNumber("WorldLootInspect.panel.maxRadius", BASE_CONFIG.panel.maxRadius)
	self._config.maxVisibleRows = tunedNumber("WorldLootInspect.maxVisibleRows", BASE_CONFIG.maxVisibleRows)

	self._wgm:updatePanel(PANEL_NAME, {
		group = self._config.groupName,
		offset = self._config.offset,
		maxRadius = self._config.maxRadius,
		lerpSpeed = self._config.lerpSpeed,
		followMode = "target",
		faceMode = "camera",
	})
end

function WorldLootInspectRuntime:setEntries(entries: { LootEntry }, selectedIndex: number, callbacks: Callbacks?)
	self._entries = table.clone(entries)
	self._selectedIndex = selectedIndex
	self._callbacks = callbacks
	self:refresh()
end

function WorldLootInspectRuntime:setSelectedIndex(selectedIndex: number)
	self._selectedIndex = selectedIndex
	self:_applySelectionVisuals()
end

function WorldLootInspectRuntime:clear()
	self._entries = {}
	self._selectedIndex = 1
	self._callbacks = nil
	self:refresh()
end

function WorldLootInspectRuntime:_refreshCanvasSize()
	if not self._listContainer or not self._listLayout then
		return
	end
	local contentY = self._listLayout.AbsoluteContentSize.Y
	self._listContainer.CanvasSize = UDim2.fromOffset(0, contentY)
end

function WorldLootInspectRuntime:_setVisible(visible: boolean)
	if self._visible == visible then
		return
	end
	self._visible = visible
	self._wgm:setPanelVisibility(PANEL_NAME, visible, 0.15, workspace)
end

function WorldLootInspectRuntime:_setFollowTarget(target: BasePart?)
	if self._followTarget == target then
		return
	end
	self._followTarget = target
	self._wgm:setPanelFollowTarget(PANEL_NAME, target)
end

function WorldLootInspectRuntime:_getIndexedEntry(uid: string): (number?, LootEntry?)
	local index = self._indexByUid[uid]
	if not index then
		return nil, nil
	end
	return index, self._entryByUid[uid]
end

function WorldLootInspectRuntime:_connectRowInteractions(uid: string, rowRuntime: RowRuntime)
	local function handleSelect()
		local callbacks = self._callbacks
		local index, entry = self:_getIndexedEntry(uid)
		if callbacks and callbacks.onSelect and index and entry then
			callbacks.onSelect(index, entry)
		end
	end

	local function handlePickup()
		local callbacks = self._callbacks
		local index, entry = self:_getIndexedEntry(uid)
		if callbacks and callbacks.onPickup and index and entry then
			callbacks.onPickup(index, entry)
		end
	end

	rowRuntime.root.MouseEnter:Connect(handleSelect)
	if rowRuntime.pickupButton then
		rowRuntime.pickupButton.MouseEnter:Connect(handleSelect)
		rowRuntime.pickupButton.MouseButton1Click:Connect(handlePickup)
	end
end

function WorldLootInspectRuntime:_createRow(uid: string): RowRuntime?
	local listContainer = self._listContainer
	local rowTemplate = self._rowTemplate
	if not listContainer or not rowTemplate then
		return nil
	end

	local row = rowTemplate:Clone()
	row.Name = `Row_{uid}`
	row.Visible = true
	row:SetAttribute("RuntimeLootRow", true)
	restoreOriginalVisualState(row)
	row.Parent = listContainer

	local binder = PanelBinder.new(row)
	local selectionNode = binder:find({ "SelectionFrame" }, nil)
	local rarityNode = binder:find({ "RarityFrame" }, nil)
	local rowRuntime: RowRuntime = {
		root = row,
		icon = binder:find({ "Icon" }, "ImageLabel") :: ImageLabel?,
		nameLabel = binder:find({ "NameLabel" }, "TextLabel") :: TextLabel?,
		stackLabel = binder:find({ "StackLabel" }, "TextLabel") :: TextLabel?,
		hintLabel = binder:find({ "HintLabel" }, "TextLabel") :: TextLabel?,
		pickupButton = binder:find({ "PickupButton" }, "GuiButton") :: GuiButton?,
		selectionFrame = if selectionNode and selectionNode:IsA("GuiObject") then selectionNode else nil,
		rarityFrame = if rarityNode and rarityNode:IsA("GuiObject") then rarityNode else nil,
	}
	self:_connectRowInteractions(uid, rowRuntime)
	self._rowsByUid[uid] = rowRuntime
	return rowRuntime
end

function WorldLootInspectRuntime:_destroyMissingRows(seen: { [string]: boolean })
	for uid, rowRuntime in pairs(self._rowsByUid) do
		if not seen[uid] then
			rowRuntime.root:Destroy()
			self._rowsByUid[uid] = nil
		end
	end
end

function WorldLootInspectRuntime:_clearAllRows()
	for uid, rowRuntime in pairs(self._rowsByUid) do
		rowRuntime.root:Destroy()
		self._rowsByUid[uid] = nil
	end
	self._orderedUids = {}
	self._entryByUid = {}
	self._indexByUid = {}
end

function WorldLootInspectRuntime:_applySelectionVisuals()
	local selectedUid = self._orderedUids[self._selectedIndex]
	for uid, rowRuntime in pairs(self._rowsByUid) do
		local isSelected = uid == selectedUid
		if rowRuntime.hintLabel then
			rowRuntime.hintLabel.Text = if isSelected then "E Pick Up" else ""
			rowRuntime.hintLabel.Visible = rowRuntime.hintLabel.Text ~= ""
		end
		if rowRuntime.selectionFrame then
			rowRuntime.selectionFrame.Visible = isSelected
		end
	end
end

function WorldLootInspectRuntime:_applyRow(entry: LootEntry, index: number)
	local uid = entry.uid
	local rowRuntime = self._rowsByUid[uid] or self:_createRow(uid)
	if not rowRuntime then
		return
	end

	rowRuntime.root.LayoutOrder = index
	rowRuntime.root.Visible = true

	local def = Registry.get(entry.itemId)
	if rowRuntime.icon then
		rowRuntime.icon.Image = if def and def.icon then def.icon else ""
		rowRuntime.icon.Visible = rowRuntime.icon.Image ~= ""
	end
	if rowRuntime.nameLabel then
		rowRuntime.nameLabel.Text = entry.displayName
	end
	if rowRuntime.stackLabel then
		rowRuntime.stackLabel.Text = if type(entry.stackSize) == "number" and entry.stackSize > 1 then tostring(entry.stackSize) else ""
		rowRuntime.stackLabel.Visible = rowRuntime.stackLabel.Text ~= ""
	end
	applyRarityVisual(rowRuntime.rarityFrame, entry.rarity)
end

function WorldLootInspectRuntime:refresh()
	if not self._panelPart then
		return
	end

	local listContainer = self._listContainer
	local rowTemplate = self._rowTemplate
	if not listContainer or not rowTemplate then
		self:_setVisible(false)
		return
	end

	local entryCount = #self._entries
	if entryCount == 0 then
		self:_clearAllRows()
		self:_setFollowTarget(nil)
		self:_setVisible(false)
		return
	end

	local lead = self._entries[1]
	self:_setFollowTarget(lead.part)
	self._wgm:setPanelFollowMode(PANEL_NAME, "target")
	self:_setVisible(true)

	setOptionalText(self._titleLabel, if entryCount == 1 then "Nearby Loot" else `Nearby Loot ({entryCount})`)
	setOptionalText(self._hintLabel, self._config.hintText)

	self._orderedUids = {}
	self._entryByUid = {}
	self._indexByUid = {}
	local seen: { [string]: boolean } = {}
	for index = 1, entryCount do
		local entry = self._entries[index]
		seen[entry.uid] = true
		self._orderedUids[index] = entry.uid
		self._entryByUid[entry.uid] = entry
		self._indexByUid[entry.uid] = index
		self:_applyRow(entry, index)
	end

	self:_destroyMissingRows(seen)
	self:_applySelectionVisuals()
	self:_refreshCanvasSize()
end

function WorldLootInspectRuntime:destroy()
	if self._tuneConn then
		self._tuneConn()
		self._tuneConn = nil
	end
	if self._panelPart then
		self._panelPart:Destroy()
		self._panelPart = nil
	end
end

local DEFAULT_CONFIG: Config = {
	groupName = BASE_CONFIG.groupName,
	offset = BASE_CONFIG.panel.offset,
	lerpSpeed = BASE_CONFIG.panel.lerpSpeed,
	maxRadius = BASE_CONFIG.panel.maxRadius,
	maxVisibleRows = BASE_CONFIG.maxVisibleRows,
	hintText = "E Pick Up  |  Alt Interact",
}

local _instance: any = nil

local function getOrCreate()
	if _instance then
		return _instance
	end
	_instance = WorldLootInspectRuntime.new(DEFAULT_CONFIG)
	if not _instance:isAvailable() then
		_instance:destroy()
		_instance = nil
		return nil
	end
	return _instance
end

return {
	new = WorldLootInspectRuntime.new,
	get = getOrCreate,
	tryInit = getOrCreate,
}
