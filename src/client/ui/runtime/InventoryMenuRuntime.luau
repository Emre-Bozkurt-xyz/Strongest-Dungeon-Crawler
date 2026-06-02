--!strict
-- InventoryMenuRuntime: world-space inventory panel runtime.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldGUIManager = require(script.Parent.Parent.Parent.WorldGUIManager)
local InventoryClient = require(script.Parent.Parent.Parent.Inventory.InventoryClient)
local Registry = require(ReplicatedStorage.Shared.items.Registry)
local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)
local Config = require(ReplicatedStorage.Shared.Config)
local DevTuningService = require(script.Parent.Parent.Parent.dev.DevTuningService)
local PanelTemplateResolver = require(script.Parent.PanelTemplateResolver)
local PanelBinder = require(script.Parent.PanelBinder)
local SlotVisuals = require(script.Parent.SlotVisuals)

local InventoryMenuRuntime = {}
InventoryMenuRuntime.__index = InventoryMenuRuntime

type MenuView = "system" | "inventory" | "equipment"
type SlotNodes = SlotVisuals.SlotNodes

local UIMenuConfig = Config.UIMenu
local GROUP_NAME = UIMenuConfig.groupName
local INVENTORY_PANEL_CONFIG = UIMenuConfig.panels.InventoryPanel
local MENU_GROUP_PARAMS = UIMenuConfig.groupParams
local INVENTORY_PANEL_OFFSET = INVENTORY_PANEL_CONFIG.offset
local MENU_PANEL_PLAYER_OFFSET = INVENTORY_PANEL_CONFIG.playerSpaceOffset
local FACE_BLEND = INVENTORY_PANEL_CONFIG.faceBlend
local LERP_SPEED = MENU_GROUP_PARAMS.lerpSpeed
local MIN_RADIUS = MENU_GROUP_PARAMS.minRadius
local MAX_RADIUS = MENU_GROUP_PARAMS.maxRadius
local MENU_PANEL_MAX_RADIUS = INVENTORY_PANEL_CONFIG.maxRadius

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

local function tunedTable(path: string, fallback: { [string]: any }): { [string]: any }
	local value = DevTuningService.get(path)
	return if type(value) == "table" then value else fallback
end

local function applyUIMenuTuning()
	GROUP_NAME = tunedString("UIMenu.groupName", UIMenuConfig.groupName)
	INVENTORY_PANEL_CONFIG = tunedTable("UIMenu.panels.InventoryPanel", UIMenuConfig.panels.InventoryPanel)
	MENU_GROUP_PARAMS = tunedTable("UIMenu.groupParams", UIMenuConfig.groupParams)

	INVENTORY_PANEL_OFFSET = tunedVector3("UIMenu.panels.InventoryPanel.offset", UIMenuConfig.panels.InventoryPanel.offset)
	MENU_PANEL_PLAYER_OFFSET = tunedVector3(
		"UIMenu.panels.InventoryPanel.playerSpaceOffset",
		UIMenuConfig.panels.InventoryPanel.playerSpaceOffset
	)
	FACE_BLEND = tunedNumber("UIMenu.panels.InventoryPanel.faceBlend", UIMenuConfig.panels.InventoryPanel.faceBlend)
	LERP_SPEED = tunedNumber("UIMenu.groupParams.lerpSpeed", UIMenuConfig.groupParams.lerpSpeed)
	MIN_RADIUS = tunedNumber("UIMenu.groupParams.minRadius", UIMenuConfig.groupParams.minRadius)
	MAX_RADIUS = tunedNumber("UIMenu.groupParams.maxRadius", UIMenuConfig.groupParams.maxRadius)
	MENU_PANEL_MAX_RADIUS = tunedNumber("UIMenu.panels.InventoryPanel.maxRadius", UIMenuConfig.panels.InventoryPanel.maxRadius)
end

applyUIMenuTuning()

local CATEGORY_ORDER = { "all", "equipment", "consumable", "material", "quest", "misc" }
local function findTemplate(name: string): BasePart?
	return PanelTemplateResolver.resolveWorldPart(name)
end

function InventoryMenuRuntime.new()
	local self = setmetatable({}, InventoryMenuRuntime)

	self.inventoryPanel = nil :: BasePart?
	self.inventoryGrid = nil :: ScrollingFrame?
	self.inventorySlotTemplate = nil :: Frame?
	self.inventorySlots = {} :: { [number]: Frame }
	self.inventorySlotNodes = {} :: { [number]: SlotNodes }
	self.categoryBar = nil :: Frame?
	self.categoryButtonTemplate = nil :: TextButton?
	self.inventoryHandle = nil :: Frame?
	self.inventoryHandleButton = nil :: TextButton?
	self.inventoryBackground = nil :: Frame?
	self.inventoryExpanded = true
	self.currentView = "system" :: MenuView
	self.selectedCategory = "all"
	self.selectedUid = nil :: string?
	self._inspectSelectionHandler = nil :: ((string?) -> ())?
	self._disconnect = function() end
	self._tuneConn = nil :: (() -> ())?

	local inventoryTemplate = findTemplate("InventoryPanel")
	assert(inventoryTemplate, "InventoryMenuRuntime: InventoryPanel BasePart is required")

	if inventoryTemplate then
		self.inventoryPanel = inventoryTemplate:Clone()
		self.inventoryPanel.Parent = workspace
		local panelBinder = PanelBinder.new(self.inventoryPanel)
		self.inventoryBackground = panelBinder:find({ "Background" }, "Frame") :: Frame?
		self.inventoryHandle = panelBinder:find({ "Handle" }, "Frame") :: Frame?
		if self.inventoryHandle then
			local handleBinder = PanelBinder.new(self.inventoryHandle)
			self.inventoryHandleButton =
				handleBinder:find({ "TextButton", "Button" }, "TextButton") :: TextButton?
		end
		self.inventoryGrid = panelBinder:require({ "InventoryGrid" }, "ScrollingFrame", "InventoryGrid") :: ScrollingFrame
		self.inventorySlotTemplate = PanelBinder.new(self.inventoryGrid):require(
			{ "ItemSlotTemplate" },
			"Frame",
			"ItemSlotTemplate"
		) :: Frame
		self.inventorySlotTemplate.Visible = false
		self.categoryBar = panelBinder:find({ "CategoryBar" }, "Frame") :: Frame?
		if self.categoryBar then
			local categoryBinder = PanelBinder.new(self.categoryBar)
			self.categoryButtonTemplate =
				categoryBinder:find({ "CategoryButtonTemplate" }, "TextButton") :: TextButton?
			if self.categoryButtonTemplate then
				self.categoryButtonTemplate.Visible = false
			end
		end
	end

	local wgm = WorldGUIManager.getInstance()
	wgm:setGroupParams(GROUP_NAME, {
		lerpSpeed = LERP_SPEED,
		minRadius = MIN_RADIUS,
		maxRadius = MAX_RADIUS,
	})

	if self.inventoryPanel then
		wgm:registerPanel({
			name = "InventoryPanel",
			part = self.inventoryPanel,
			group = GROUP_NAME,
			faceCamera = true,
			faceMode = "playerYaw",
			faceBlend = FACE_BLEND,
			followMode = "player",
			offset = INVENTORY_PANEL_OFFSET,
			playerSpaceOffset = MENU_PANEL_PLAYER_OFFSET,
			playerOffsetMode = INVENTORY_PANEL_CONFIG.playerOffsetMode,
			maxRadius = MENU_PANEL_MAX_RADIUS,
		})
		wgm:setPanelVisibility("InventoryPanel", false, 0, workspace)
	end

	if self.categoryBar and self.categoryButtonTemplate then
		for _, category in ipairs(CATEGORY_ORDER) do
			local clone = self.categoryButtonTemplate:Clone()
			clone.Name = category
			clone.Text = category:sub(1, 1):upper() .. category:sub(2)
			clone.Visible = true
			clone.Parent = self.categoryBar
			clone.MouseButton1Click:Connect(function()
				self.selectedCategory = category
				self:refresh()
			end)
		end
	end

	if self.inventoryHandleButton then
		self.inventoryHandleButton.MouseButton1Click:Connect(function()
			if self.currentView == "system" then
				self.currentView = "inventory"
			else
				self.currentView = "system"
			end
			self:_applyMenuView()
		end)
	end

	self._disconnect = InventoryClient.onChanged(function()
		self:refresh()
	end)
	self._tuneConn = DevTuningService.subscribe("UIMenu", function()
		applyUIMenuTuning()
		self:_applyUIMenuTuningToRuntime()
	end)

	self:refresh()
	self:_applyUIMenuTuningToRuntime()

	return self
end

function InventoryMenuRuntime:_applyUIMenuTuningToRuntime()
	local wgm = WorldGUIManager.getInstance()
	wgm:setGroupParams(GROUP_NAME, {
		lerpSpeed = LERP_SPEED,
		minRadius = MIN_RADIUS,
		maxRadius = MAX_RADIUS,
	})

	if self.inventoryPanel then
		wgm:updatePanel("InventoryPanel", {
			group = GROUP_NAME,
			offset = INVENTORY_PANEL_OFFSET,
			playerSpaceOffset = MENU_PANEL_PLAYER_OFFSET,
			faceBlend = FACE_BLEND,
			maxRadius = MENU_PANEL_MAX_RADIUS,
			playerOffsetMode = tunedString(
				"UIMenu.panels.InventoryPanel.playerOffsetMode",
				UIMenuConfig.panels.InventoryPanel.playerOffsetMode
			),
		})
	end

	self:_applyMenuView()
end

function InventoryMenuRuntime:_ensureInventorySlots(capacity: number)
	if not (self.inventoryGrid and self.inventorySlotTemplate) then
		return
	end
	for i = 1, capacity do
		if not self.inventorySlots[i] then
			local slot = self.inventorySlotTemplate:Clone()
			slot.Name = `Slot_{i}`
			slot.Visible = true
			slot.Parent = self.inventoryGrid
			slot.LayoutOrder = i
			self.inventorySlots[i] = slot
			local nodes = SlotVisuals.bind(slot)
			self.inventorySlotNodes[i] = nodes
			SlotVisuals.setEmpty(slot, nodes)
			if nodes.button then
				nodes.button.MouseButton1Click:Connect(function()
					local uid = slot:GetAttribute("ItemUid")
					if type(uid) == "string" then
						self.selectedUid = uid
					else
						self.selectedUid = nil
					end
					self:_emitInspectSelection()
				end)
			end
		end
	end
end

function InventoryMenuRuntime:_filterCategory(def: ItemTypes.ItemDef): boolean
	if self.selectedCategory == "all" then
		return true
	end
	return def.category == self.selectedCategory
end

function InventoryMenuRuntime:setInspectSelectionHandler(handler: ((string?) -> ())?)
	self._inspectSelectionHandler = handler
end

function InventoryMenuRuntime:_emitInspectSelection()
	if self._inspectSelectionHandler then
		self._inspectSelectionHandler(self.selectedUid)
	end
end

function InventoryMenuRuntime:_applyMenuView()
	local wgm = WorldGUIManager.getInstance()

	if self.currentView == "system" then
		if self.inventoryPanel then
			wgm:setPanelVisibility("InventoryPanel", false, 0.2, workspace)
		end
		return
	end

	if self.currentView == "inventory" then
		if self.inventoryPanel then
			wgm:setPanelVisibility("InventoryPanel", true, 0.2, workspace)
		end
		if self.inventoryBackground then
			self.inventoryBackground.Visible = self.inventoryExpanded
		end
		if self.categoryBar then
			self.categoryBar.Visible = self.inventoryExpanded
		end
		if self.inventoryGrid then
			self.inventoryGrid.Visible = self.inventoryExpanded
		end
		return
	end

	if self.currentView == "equipment" then
		if self.inventoryPanel then
			wgm:setPanelVisibility("InventoryPanel", false, 0.2, workspace)
		end
	end
end

function InventoryMenuRuntime:refresh()
	local inv = InventoryClient.getInventory()
	local items = InventoryClient.getItems()
	if inv and self.inventoryGrid and self.inventorySlotTemplate then
		self:_ensureInventorySlots(inv.capacity)
		for i = 1, inv.capacity do
			local slotFrame = self.inventorySlots[i]
			if slotFrame then
				local slotNodes = self.inventorySlotNodes[i]
				local uid = inv.slots[i]
				if uid then
					local item = items[uid]
					local def = item and Registry.get(item.itemId)
					if item and def and self:_filterCategory(def) then
						SlotVisuals.setItem(slotFrame, item, def, slotNodes)
					else
						SlotVisuals.setEmpty(slotFrame, slotNodes)
					end
				else
					SlotVisuals.setEmpty(slotFrame, slotNodes)
				end
			end
		end
	end

	if self.selectedUid then
		local selectedItem = items[self.selectedUid]
		local selectedDef = selectedItem and Registry.get(selectedItem.itemId)
		local selectedStillInInventory = false
		if inv then
			for _, slotUid in pairs(inv.slots) do
				if slotUid == self.selectedUid then
					selectedStillInInventory = true
					break
				end
			end
		end
		if (not selectedItem) or (not selectedDef) or (not self:_filterCategory(selectedDef)) or (not selectedStillInInventory) then
			self.selectedUid = nil
			self:_emitInspectSelection()
		end
	end

	self:_applyMenuView()
end

function InventoryMenuRuntime:setMenuView(view: MenuView)
	if view ~= "inventory" then
		self.selectedUid = nil
	end
	self.currentView = view
	self:_applyMenuView()
end

function InventoryMenuRuntime:cycleMenuView(direction: number?): MenuView
	local views: { MenuView } = { "system", "inventory", "equipment" }
	local available: { MenuView } = {}
	for _, view in ipairs(views) do
		if view == "system" then
			table.insert(available, view)
		elseif view == "inventory" and self.inventoryPanel then
			table.insert(available, view)
		elseif view == "equipment" then
			table.insert(available, view)
		end
	end
	if #available == 0 then
		return self.currentView
	end
	local idx = 1
	for i, view in ipairs(available) do
		if view == self.currentView then
			idx = i
			break
		end
	end
	local dir = if (direction or 1) >= 0 then 1 else -1
	local nextIdx = idx + dir
	if nextIdx < 1 then
		nextIdx = #available
	elseif nextIdx > #available then
		nextIdx = 1
	end
	self:setMenuView(available[nextIdx])
	return self.currentView
end

function InventoryMenuRuntime:showInventory()
	self:setMenuView("inventory")
end

function InventoryMenuRuntime:showEquipment()
	self:setMenuView("equipment")
end

function InventoryMenuRuntime:showBoth()
	-- Combined view defaults to inventory as primary.
	self:setMenuView("inventory")
end

function InventoryMenuRuntime:hideAll()
	local wgm = WorldGUIManager.getInstance()
	self.currentView = "system"
	self.selectedUid = nil
	if self.inventoryPanel then
		wgm:setPanelVisibility("InventoryPanel", false, 0.2, workspace)
	end
end

function InventoryMenuRuntime:destroy()
	if self._disconnect then
		self._disconnect()
		self._disconnect = function() end
	end
	if self._tuneConn then
		self._tuneConn()
		self._tuneConn = nil
	end
	if self.inventoryPanel then
		self.inventoryPanel:Destroy()
		self.inventoryPanel = nil
	end
end

local _instance: InventoryMenuRuntime?

local function get()
	if _instance then
		return _instance
	end
	_instance = InventoryMenuRuntime.new()
	return _instance
end

local function tryInit()
	local hasInventory = findTemplate("InventoryPanel") ~= nil
	if not hasInventory then
		return nil
	end
	return get()
end

return {
	new = InventoryMenuRuntime.new,
	get = get,
	tryInit = tryInit,
	setMenuView = function(view: MenuView)
		get():setMenuView(view)
	end,
	cycleMenuView = function(direction: number?): MenuView
		return get():cycleMenuView(direction)
	end,
	getMenuView = function(): MenuView
		return get().currentView
	end,
	setInspectSelectionHandler = function(handler: ((string?) -> ())?)
		get():setInspectSelectionHandler(handler)
	end,
	destroy = function()
		if _instance then
			_instance:destroy()
			_instance = nil
		end
	end,
}
