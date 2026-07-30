--!strict
-- Owns EquipmentPanel template instantiation, world registration, visibility, and refresh pipeline.

local WorldGUIManager = require(script.Parent.Parent.Parent.WorldGUIManager)
local InventoryClient = require(script.Parent.Parent.Parent.Inventory.InventoryClient)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Registry = require(ReplicatedStorage.Shared.items.Registry)
local SharedConfig = require(ReplicatedStorage.Shared.Config)
local DevTuningService = require(script.Parent.Parent.Parent.dev.DevTuningService)
local EquipmentPanelRuntime = require(script.Parent.EquipmentPanelRuntime)
local PanelTemplateResolver = require(script.Parent.PanelTemplateResolver)

local EquipmentMenuRuntime = {}
EquipmentMenuRuntime.__index = EquipmentMenuRuntime

export type Config = {
	groupName: string,
	offset: Vector3,
	playerSpaceOffset: Vector3,
	faceBlend: number,
	maxRadius: number,
}

local PANEL_NAME = "EquipmentPanel"
local UIMenuConfig = SharedConfig.UIMenu

local function tunedString(path: string, fallback: string): string
	local v = DevTuningService.get(path)
	return if type(v) == "string" then v else fallback
end

local function tunedNumber(path: string, fallback: number): number
	local v = DevTuningService.get(path)
	return if type(v) == "number" then v else fallback
end

local function tunedVector3(path: string, fallback: Vector3): Vector3
	local v = DevTuningService.get(path)
	return if typeof(v) == "Vector3" then v else fallback
end

local DEFAULT_CONFIG: Config = {
	groupName = UIMenuConfig.groupName,
	offset = UIMenuConfig.panels.EquipmentPanel.offset,
	playerSpaceOffset = UIMenuConfig.panels.EquipmentPanel.playerSpaceOffset,
	faceBlend = UIMenuConfig.panels.EquipmentPanel.faceBlend,
	maxRadius = UIMenuConfig.panels.EquipmentPanel.maxRadius,
}

function EquipmentMenuRuntime.new(config: Config)
	local self = setmetatable({}, EquipmentMenuRuntime)
	self._wgm = WorldGUIManager.getInstance()
	self._config = config
	self._panelPart = nil :: BasePart?
	self._slotRuntime = nil :: any
	self._selectedUid = nil :: string?
	self._inspectSelectionHandler = nil :: ((string?) -> ())?
	self._disconnect = nil :: (() -> ())?
	self._tuneConn = nil :: (() -> ())?

	local template = PanelTemplateResolver.resolveWorldPart(PANEL_NAME)
	if template then
		self._panelPart = template:Clone()
		self._panelPart.Parent = workspace
		self._wgm:registerPanel({
			name = PANEL_NAME,
			part = self._panelPart,
			group = config.groupName,
			faceCamera = true,
			faceMode = "playerYaw",
			faceBlend = config.faceBlend,
			followMode = "player",
			offset = config.offset,
			playerSpaceOffset = config.playerSpaceOffset,
			playerOffsetMode = UIMenuConfig.panels.EquipmentPanel.playerOffsetMode,
			maxRadius = config.maxRadius,
		})
		self._wgm:setPanelVisibility(PANEL_NAME, false, 0, workspace)
		self._slotRuntime = EquipmentPanelRuntime.new(self._panelPart, function(report: string)
			warn(report)
		end)
		self._slotRuntime:setInspectSelectionHandler(function(uid: string?)
			self._selectedUid = uid
			self:_emitInspectSelection()
		end)
		self._disconnect = InventoryClient.onChanged(function()
			self:refreshFromClient()
		end)
		self:refreshFromClient()
	end

	self._tuneConn = DevTuningService.subscribe("UIMenu", function()
		self:_applyUIMenuTuning()
	end)
	self:_applyUIMenuTuning()

	return self
end

function EquipmentMenuRuntime:setInspectSelectionHandler(handler: ((string?) -> ())?)
	self._inspectSelectionHandler = handler
end

function EquipmentMenuRuntime:_emitInspectSelection()
	if self._inspectSelectionHandler then
		self._inspectSelectionHandler(self._selectedUid)
	end
end

function EquipmentMenuRuntime:clearSelection()
	if self._selectedUid == nil then
		if self._slotRuntime then
			self._slotRuntime:clearSelection()
		end
		return
	end
	self._selectedUid = nil
	if self._slotRuntime then
		self._slotRuntime:clearSelection()
	end
	self:_emitInspectSelection()
end

function EquipmentMenuRuntime:isAvailable(): boolean
	return self._panelPart ~= nil
end

function EquipmentMenuRuntime:setVisible(visible: boolean, transition: number?)
	if not self._panelPart then
		return
	end
	self._wgm:setPanelVisibility(PANEL_NAME, visible, transition or 0.2, workspace)
end

function EquipmentMenuRuntime:_applyUIMenuTuning()
	if not self._panelPart then
		return
	end

	self._config.groupName = tunedString("UIMenu.groupName", UIMenuConfig.groupName)
	self._config.offset = tunedVector3("UIMenu.panels.EquipmentPanel.offset", UIMenuConfig.panels.EquipmentPanel.offset)
	self._config.playerSpaceOffset = tunedVector3(
		"UIMenu.panels.EquipmentPanel.playerSpaceOffset",
		UIMenuConfig.panels.EquipmentPanel.playerSpaceOffset
	)
	self._config.faceBlend = tunedNumber("UIMenu.panels.EquipmentPanel.faceBlend", UIMenuConfig.panels.EquipmentPanel.faceBlend)
	self._config.maxRadius = tunedNumber("UIMenu.panels.EquipmentPanel.maxRadius", UIMenuConfig.panels.EquipmentPanel.maxRadius)

	self._wgm:updatePanel(PANEL_NAME, {
		group = self._config.groupName,
		offset = self._config.offset,
		playerSpaceOffset = self._config.playerSpaceOffset,
		faceBlend = self._config.faceBlend,
		maxRadius = self._config.maxRadius,
		playerOffsetMode = tunedString(
			"UIMenu.panels.EquipmentPanel.playerOffsetMode",
			UIMenuConfig.panels.EquipmentPanel.playerOffsetMode
		),
	})
end

function EquipmentMenuRuntime:refresh(
	equipState: any,
	inventoryState: any,
	itemsByUid: { [string]: any },
	registryGet: (string) -> any
)
	if not self._slotRuntime then
		return
	end
	self._slotRuntime:refresh(equipState, inventoryState, itemsByUid, registryGet)
end

function EquipmentMenuRuntime:refreshFromClient()
	if not self._slotRuntime then
		return
	end
	local equip = InventoryClient.getEquipment()
	local inventory = InventoryClient.getInventory()
	local items = InventoryClient.getItems()
	self:refresh(equip, inventory, items, function(itemId: string)
		return Registry.get(itemId)
	end)

	if self._selectedUid then
		local selectedItem = items[self._selectedUid]
		local selectedStillEquipped = false
		if equip then
			for _, slotUid in pairs(equip.slots) do
				if slotUid == self._selectedUid then
					selectedStillEquipped = true
					break
				end
			end
		end
		if (not selectedItem) or (not selectedStillEquipped) then
			self:clearSelection()
		end
	end
end

function EquipmentMenuRuntime:destroy()
	if self._disconnect then
		self._disconnect()
		self._disconnect = nil
	end
	if self._tuneConn then
		self._tuneConn()
		self._tuneConn = nil
	end
	if self._panelPart then
		self._panelPart:Destroy()
		self._panelPart = nil
	end
	self._slotRuntime = nil
end

local _instance: any = nil

local function getOrCreate()
	if _instance then
		return _instance
	end
	_instance = EquipmentMenuRuntime.new(DEFAULT_CONFIG)
	if not _instance:isAvailable() then
		_instance = nil
		return nil
	end
	return _instance
end

return {
	new = EquipmentMenuRuntime.new,
	get = getOrCreate,
	tryInit = getOrCreate,
	show = function()
		local inst = getOrCreate()
		if not inst then
			return
		end
		inst:setVisible(true, 0.2)
	end,
	hide = function()
		local inst = getOrCreate()
		if not inst then
			return
		end
		inst:setVisible(false, 0.2)
	end,
	refresh = function()
		local inst = getOrCreate()
		if not inst then
			return
		end
		inst:refreshFromClient()
	end,
	setInspectSelectionHandler = function(handler: ((string?) -> ())?)
		local inst = getOrCreate()
		if not inst then
			return
		end
		inst:setInspectSelectionHandler(handler)
	end,
	clearSelection = function()
		local inst = getOrCreate()
		if not inst then
			return
		end
		inst:clearSelection()
	end,
	isAvailable = function(): boolean
		local inst = getOrCreate()
		return inst ~= nil and inst:isAvailable()
	end,
	destroy = function()
		if _instance then
			_instance:destroy()
			_instance = nil
		end
	end,
}
