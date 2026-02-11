--!strict
-- InventoryUIController: world-space inventory + equipment UI wiring.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldGUIManager = require(script.Parent.Parent.Parent.WorldGUIManager)
local InventoryClient = require(script.Parent.Parent.Parent.Inventory.InventoryClient)
local Registry = require(ReplicatedStorage.Shared.items.Registry)
local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)

local InventoryUIController = {}
InventoryUIController.__index = InventoryUIController

type MenuView = "system" | "inventory" | "equipment"

local GROUP_NAME = "menu"
local INVENTORY_PANEL_OFFSET = Vector3.new(0, 0.2, 0)
local MENU_PANEL_PLAYER_OFFSET = Vector3.new(0.3, 1.0, 3.8)
local EQUIPMENT_PANEL_OFFSET = Vector3.new(0, 0.2, 0)
local INSPECT_PANEL_OFFSET = Vector3.new(0, 0.2, 0)
local FACE_BLEND = 0.35
local LERP_SPEED = 14
local MIN_RADIUS = 2.7
local MAX_RADIUS = 8.0
local MENU_PANEL_MAX_RADIUS = 16.0
local SHOW_STUB_ACTIONS = false
local MENU_LAYOUT_SPACING = 0.45
local MENU_LAYOUT_ARC_RADIUS = 8.5
local MENU_LAYOUT_ARC_DEPTH = 0.28

local CATEGORY_ORDER = { "all", "equipment", "consumable", "material", "quest", "misc" }
local RARITY_COLORS = {
	normal = Color3.fromRGB(200, 200, 200),
	magic = Color3.fromRGB(88, 152, 255),
	rare = Color3.fromRGB(255, 210, 90),
	unique = Color3.fromRGB(220, 140, 60),
}

local function findTemplate(name: string): BasePart?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local worldUI = assets and assets:FindFirstChild("WorldUI")
	local template = worldUI and worldUI:FindFirstChild(name)
	if template and template:IsA("BasePart") then
		return template
	end
	return nil
end

local function findDescendant(root: Instance, name: string, className: string?): Instance?
	local node = root:FindFirstChild(name, true)
	if node and (not className or node.ClassName == className) then
		return node
	end
	return nil
end

local function getSlotNodes(slot: Instance)
	local icon = findDescendant(slot, "Icon", "ImageLabel") :: ImageLabel?
	local stack = findDescendant(slot, "StackLabel", "TextLabel") :: TextLabel?
	local rarity = findDescendant(slot, "RarityFrame", "Frame") :: Frame?
	local button = findDescendant(slot, "Button", "TextButton") :: TextButton?
	return icon, stack, rarity, button
end

local function clearChildrenExceptTemplate(container: Instance, template: Instance?)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("TextButton") and child ~= template then
			child:Destroy()
		end
	end
end

local function setSlotEmpty(slot: Instance)
	local icon, stack, rarity = getSlotNodes(slot)
	if icon then
		icon.Image = ""
		icon.Visible = false
	end
	if stack then
		stack.Text = ""
		stack.Visible = false
	end
	if rarity then
		rarity.Visible = false
	end
	slot:SetAttribute("ItemUid", nil)
end

local function setSlotItem(slot: Instance, item: ItemTypes.ItemInstance, def: ItemTypes.ItemDef)
	local icon, stack, rarity = getSlotNodes(slot)
	if icon then
		icon.Image = def.icon or ""
		icon.Visible = icon.Image ~= ""
	end
	if stack then
		stack.Text = item.stackSize > 1 and tostring(item.stackSize) or ""
		stack.Visible = stack.Text ~= ""
	end
	if rarity then
		local color = RARITY_COLORS[def.rarity] or RARITY_COLORS.normal
		rarity.BackgroundColor3 = color
		rarity.Visible = true
	end
	slot:SetAttribute("ItemUid", item.uid)
end

local function getItemLocation(uid: string, inv: ItemTypes.InventoryState?, equip: ItemTypes.EquipmentState?)
	if inv then
		for slot, slotUid in pairs(inv.slots) do
			if slotUid == uid then
				return { container = "inventory", slot = slot }
			end
		end
	end
	if equip then
		for slot, slotUid in pairs(equip.slots) do
			if slotUid == uid then
				return { container = "equipment", slot = slot }
			end
		end
	end
	return nil
end

local function pickEquipSlot(def: ItemTypes.ItemDef, equip: ItemTypes.EquipmentState?): string?
	if not def.equipSlots or #def.equipSlots == 0 then
		return nil
	end
	if equip then
		for _, slot in ipairs(def.equipSlots) do
			if equip.slots[slot] == nil then
				return slot
			end
		end
	end
	return def.equipSlots[1]
end

local function metaFlag(meta: { [string]: any }?, key: string): boolean
	if not meta then
		return false
	end
	return meta[key] == true
end

function InventoryUIController.new()
	local self = setmetatable({}, InventoryUIController)

	self.inventoryPanel = nil :: BasePart?
	self.equipmentPanel = nil :: BasePart?
	self.inspectPanelPart = nil :: BasePart?
	self.inventoryGrid = nil :: ScrollingFrame?
	self.inventorySlotTemplate = nil :: Frame?
	self.inventorySlots = {} :: { [number]: Frame }
	self.equipmentSlotsRoot = nil :: Frame?
	self.equipmentSlots = {} :: { [string]: Frame }
	self.inspectPanel = nil :: Frame?
	self.inspectStatsContainer = nil :: Frame?
	self.inspectStatTemplate = nil :: TextLabel?
	self.inspectActionBar = nil :: Frame?
	self.inspectActionTemplate = nil :: TextButton?
	self.externalInspect = nil :: {
		def: ItemTypes.ItemDef,
		item: ItemTypes.ItemInstance?,
		actions: { [number]: { id: string, label: string, enabled: boolean?, handler: () -> () } }?,
	}?
	self.categoryBar = nil :: Frame?
	self.categoryButtonTemplate = nil :: TextButton?
	self.inventoryHandle = nil :: Frame?
	self.inventoryHandleButton = nil :: TextButton?
	self.inventoryBackground = nil :: Frame?
	self.inventoryExpanded = true
	self.currentView = "system" :: MenuView
	self.inspectVisible = false
	self.selectedCategory = "all"
	self.selectedUid = nil :: string?
	self._disconnect = function() end

	local inventoryTemplate = findTemplate("InventoryPanel")
	local equipmentTemplate = findTemplate("EquipmentPanel")
	local inspectTemplate = findTemplate("ItemInspectPanel")
	assert(
		inventoryTemplate or equipmentTemplate or inspectTemplate,
		"InventoryUIController: InventoryPanel, EquipmentPanel, or ItemInspectPanel BasePart is required"
	)

	if inventoryTemplate then
		self.inventoryPanel = inventoryTemplate:Clone()
		self.inventoryPanel.Parent = workspace
		self.inventoryBackground = findDescendant(self.inventoryPanel, "Background", "Frame") :: Frame?
		self.inventoryHandle = findDescendant(self.inventoryPanel, "Handle", "Frame") :: Frame?
		if self.inventoryHandle then
			self.inventoryHandleButton = findDescendant(self.inventoryHandle, "TextButton", "TextButton") :: TextButton?
			if not self.inventoryHandleButton then
				self.inventoryHandleButton = findDescendant(self.inventoryHandle, "Button", "TextButton") :: TextButton?
			end
		end
		self.inventoryGrid = findDescendant(self.inventoryPanel, "InventoryGrid", "ScrollingFrame") :: ScrollingFrame?
		assert(self.inventoryGrid, "InventoryUIController: InventoryGrid not found in InventoryPanel")
		self.inventorySlotTemplate = findDescendant(self.inventoryGrid, "ItemSlotTemplate", "Frame") :: Frame?
		assert(self.inventorySlotTemplate, "InventoryUIController: ItemSlotTemplate not found in InventoryGrid")
		self.inventorySlotTemplate.Visible = false
		self.categoryBar = findDescendant(self.inventoryPanel, "CategoryBar", "Frame") :: Frame?
		if self.categoryBar then
			self.categoryButtonTemplate =
				findDescendant(self.categoryBar, "CategoryButtonTemplate", "TextButton") :: TextButton?
			if self.categoryButtonTemplate then
				self.categoryButtonTemplate.Visible = false
			end
		end
	end

	if equipmentTemplate then
		self.equipmentPanel = equipmentTemplate:Clone()
		self.equipmentPanel.Parent = workspace
		self.equipmentSlotsRoot = findDescendant(self.equipmentPanel, "EquipmentSlots", "Frame") :: Frame?
		assert(self.equipmentSlotsRoot, "InventoryUIController: EquipmentSlots not found in EquipmentPanel")
	end

	if inspectTemplate then
		self.inspectPanelPart = inspectTemplate:Clone()
		self.inspectPanelPart.Parent = workspace
		local inspectRoot = findDescendant(self.inspectPanelPart, "Root", "Frame")
		self.inspectPanel = (inspectRoot or findDescendant(self.inspectPanelPart, "Background", "Frame")) :: Frame?
	end

	if self.inspectPanel then
		self.inspectStatsContainer = findDescendant(self.inspectPanel, "StatsContainer", "Frame") :: Frame?
		if not self.inspectStatsContainer then
			self.inspectStatsContainer = findDescendant(self.inspectPanel, "InfoContainer", "Frame") :: Frame?
		end
		self.inspectStatTemplate = findDescendant(self.inspectPanel, "StatLineTemplate", "TextLabel") :: TextLabel?
		if not self.inspectStatTemplate then
			self.inspectStatTemplate = findDescendant(self.inspectPanel, "ContentTemplate", "TextLabel") :: TextLabel?
		end
		if self.inspectStatTemplate then
			self.inspectStatTemplate.Visible = false
		end
		self.inspectActionBar = findDescendant(self.inspectPanel, "ActionBar", "Frame") :: Frame?
		if self.inspectActionBar then
			self.inspectActionTemplate =
				findDescendant(self.inspectActionBar, "ActionButtonTemplate", "TextButton") :: TextButton?
			if self.inspectActionTemplate then
				self.inspectActionTemplate.Visible = false
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
			playerOffsetMode = "yaw",
			maxRadius = MENU_PANEL_MAX_RADIUS,
		})
		wgm:setPanelVisibility("InventoryPanel", false, 0, workspace)
	end

	if self.equipmentPanel then
		wgm:registerPanel({
			name = "EquipmentPanel",
			part = self.equipmentPanel,
			group = GROUP_NAME,
			faceCamera = true,
			faceMode = "playerYaw",
			faceBlend = FACE_BLEND,
			followMode = "player",
			offset = EQUIPMENT_PANEL_OFFSET,
			playerSpaceOffset = MENU_PANEL_PLAYER_OFFSET,
			playerOffsetMode = "yaw",
			maxRadius = MENU_PANEL_MAX_RADIUS,
		})
		wgm:setPanelVisibility("EquipmentPanel", false, 0, workspace)
	end

	if self.inspectPanelPart then
		wgm:registerPanel({
			name = "ItemInspectPanel",
			part = self.inspectPanelPart,
			group = GROUP_NAME,
			faceCamera = true,
			faceMode = "playerYaw",
			faceBlend = FACE_BLEND,
			followMode = "player",
			offset = INSPECT_PANEL_OFFSET,
			playerSpaceOffset = MENU_PANEL_PLAYER_OFFSET,
			playerOffsetMode = "yaw",
			maxRadius = MENU_PANEL_MAX_RADIUS,
		})
		wgm:setPanelVisibility("ItemInspectPanel", false, 0, workspace)
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

	if self.equipmentSlotsRoot then
		for _, child in ipairs(self.equipmentSlotsRoot:GetChildren()) do
			if child:IsA("Frame") then
				self.equipmentSlots[child.Name] = child
				setSlotEmpty(child)
			end
		end
	end

	self._disconnect = InventoryClient.onChanged(function()
		self:refresh()
	end)

	self:refresh()

	return self
end

function InventoryUIController:_ensureInventorySlots(capacity: number)
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
			setSlotEmpty(slot)
			local _, _, _, button = getSlotNodes(slot)
			if button then
				button.MouseButton1Click:Connect(function()
					local uid = slot:GetAttribute("ItemUid")
					if type(uid) == "string" then
						self.selectedUid = uid
					else
						self.selectedUid = nil
					end
					self:updateInspect()
				end)
			end
		end
	end
end

function InventoryUIController:_filterCategory(def: ItemTypes.ItemDef): boolean
	if self.selectedCategory == "all" then
		return true
	end
	return def.category == self.selectedCategory
end

function InventoryUIController:_setMenuLayout(order: { string })
	if #order == 0 then
		return
	end
	WorldGUIManager.getInstance():setGroupLayout(GROUP_NAME, {
		order = order,
		anchor = order[1],
		spacing = MENU_LAYOUT_SPACING,
		includeHidden = false,
		-- These menu panels are player-follow panels, so layout must run in the same space.
		space = "player",
		surface = "arc",
		arcRadius = MENU_LAYOUT_ARC_RADIUS,
		arcDepthScale = MENU_LAYOUT_ARC_DEPTH,
		-- Keep menu arc deterministic: do not auto-flip depth based on camera relation.
		-- Negative sign pulls side panels slightly back toward the player/camera for readability.
		arcDepthSign = -1,
	})
end

function InventoryUIController:_setMenuCenterWeights(weights: { [string]: number })
	WorldGUIManager.getInstance():setGroupParams(GROUP_NAME, {
		centerWeights = weights,
	})
end

function InventoryUIController:_resetInspectFollow()
	if not self.inspectPanelPart then
		return
	end
	local wgm = WorldGUIManager.getInstance()
	wgm:setPanelFollowModeLock("ItemInspectPanel", false)
	wgm:setPanelFollowTarget("ItemInspectPanel", nil)
	wgm:setPanelFollowMode("ItemInspectPanel", "player")
	wgm:setPanelPlayerSpaceOffset("ItemInspectPanel", MENU_PANEL_PLAYER_OFFSET)
end

function InventoryUIController:_shouldShowInspect(): boolean
	if self.externalInspect ~= nil then
		return self.inspectVisible
	end
	return self.inspectVisible and self.currentView ~= "system"
end

function InventoryUIController:_applyMenuView()
	local wgm = WorldGUIManager.getInstance()
	if self.externalInspect ~= nil then
		self:_setMenuCenterWeights({
			ItemInspectPanel = 2.4,
			_default = 1.0,
		})
		self:_setMenuLayout({ "ItemInspectPanel" })
		self:_resetInspectFollow()
		if self.inventoryPanel then
			wgm:setPanelVisibility("InventoryPanel", false, 0.2, workspace)
		end
		if self.equipmentPanel then
			wgm:setPanelVisibility("EquipmentPanel", false, 0.2, workspace)
		end
		if self.inspectPanelPart then
			wgm:setPanelVisibility("ItemInspectPanel", self.inspectVisible, 0.2, workspace)
		end
		return
	end

	if self.currentView == "system" then
		self:_setMenuCenterWeights({
			SystemPanel = 2.5,
			_default = 0.75,
		})
		self:_setMenuLayout({ "SystemPanel" })
		self:_resetInspectFollow()
		if self.inventoryPanel then
			wgm:setPanelVisibility("InventoryPanel", false, 0.2, workspace)
		end
		if self.equipmentPanel then
			wgm:setPanelVisibility("EquipmentPanel", false, 0.2, workspace)
		end
		if self.inspectPanelPart then
			wgm:setPanelVisibility("ItemInspectPanel", false, 0.2, workspace)
		end
		return
	end

	if self.currentView == "inventory" then
		local showInspect = self:_shouldShowInspect()
		self:_setMenuCenterWeights({
			InventoryPanel = 2.8,
			ItemInspectPanel = 0.85,
			_default = 0.6,
		})
		if showInspect then
			self:_setMenuLayout({ "InventoryPanel", "ItemInspectPanel" })
		else
			self:_setMenuLayout({ "InventoryPanel" })
		end
		if self.inventoryPanel then
			wgm:setPanelVisibility("InventoryPanel", true, 0.2, workspace)
		end
		if self.equipmentPanel then
			wgm:setPanelVisibility("EquipmentPanel", false, 0.2, workspace)
		end
		if self.inspectPanelPart then
			self:_resetInspectFollow()
			wgm:setPanelVisibility("ItemInspectPanel", showInspect, 0.2, workspace)
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
		local showInspect = self:_shouldShowInspect()
		self:_setMenuCenterWeights({
			EquipmentPanel = 2.8,
			ItemInspectPanel = 0.85,
			_default = 0.6,
		})
		if showInspect then
			self:_setMenuLayout({ "EquipmentPanel", "ItemInspectPanel" })
		else
			self:_setMenuLayout({ "EquipmentPanel" })
		end
		if self.equipmentPanel then
			wgm:setPanelVisibility("EquipmentPanel", true, 0.2, workspace)
		end
		if self.inventoryPanel then
			wgm:setPanelVisibility("InventoryPanel", false, 0.2, workspace)
		end
		if self.inspectPanelPart then
			self:_resetInspectFollow()
			wgm:setPanelVisibility("ItemInspectPanel", showInspect, 0.2, workspace)
		end
	end
end

function InventoryUIController:refresh()
	local inv = InventoryClient.getInventory()
	local items = InventoryClient.getItems()
	if inv and self.inventoryGrid and self.inventorySlotTemplate then
		self:_ensureInventorySlots(inv.capacity)
		for i = 1, inv.capacity do
			local slotFrame = self.inventorySlots[i]
			if slotFrame then
				local uid = inv.slots[i]
				if uid then
					local item = items[uid]
					local def = item and Registry.get(item.itemId)
					if item and def and self:_filterCategory(def) then
						setSlotItem(slotFrame, item, def)
					else
						setSlotEmpty(slotFrame)
					end
				else
					setSlotEmpty(slotFrame)
				end
			end
		end
	end

	if self.equipmentSlotsRoot then
		local equip = InventoryClient.getEquipment()
		if equip then
			for slotName, slotFrame in pairs(self.equipmentSlots) do
				local uid = equip.slots[slotName]
				if uid then
					local item = items[uid]
					local def = item and Registry.get(item.itemId)
					if item and def then
						setSlotItem(slotFrame, item, def)
					else
						setSlotEmpty(slotFrame)
					end
				else
					setSlotEmpty(slotFrame)
				end
			end
		end
	end

	self:updateInspect()
end

function InventoryUIController:updateInspect()
	if not self.inspectPanel then
		return
	end
	local items = InventoryClient.getItems()
	local inv = InventoryClient.getInventory()
	local equip = InventoryClient.getEquipment()
	local uid = self.selectedUid
	local item = uid and items[uid] or nil
	local def = item and Registry.get(item.itemId) or nil
	local location = uid and getItemLocation(uid, inv, equip) or nil
	local external = self.externalInspect
	if external then
		def = external.def
		item = external.item
		location = nil
	end

	local icon = findDescendant(self.inspectPanel, "Icon", "ImageLabel") :: ImageLabel?
	local nameLabel = findDescendant(self.inspectPanel, "NameLabel", "TextLabel") :: TextLabel?
	if not nameLabel then
		nameLabel = findDescendant(self.inspectPanel, "Title", "TextLabel") :: TextLabel?
	end
	local rarityLabel = findDescendant(self.inspectPanel, "RarityLabel", "TextLabel") :: TextLabel?

	if not def then
		self.inspectVisible = false
		if icon then
			icon.Visible = false
		end
		if nameLabel then
			nameLabel.Text = ""
		end
		if rarityLabel then
			rarityLabel.Text = ""
		end
		if self.inspectStatsContainer and self.inspectStatTemplate then
			for _, child in ipairs(self.inspectStatsContainer:GetChildren()) do
				if child:IsA("TextLabel") and child ~= self.inspectStatTemplate then
					child:Destroy()
				end
			end
		end
		self:_applyMenuView()
		return
	end

	self.inspectVisible = true

	if icon then
		icon.Image = def.icon or ""
		icon.Visible = icon.Image ~= ""
	end
	if nameLabel then
		nameLabel.Text = def.name
	end
	if rarityLabel then
		rarityLabel.Text = def.rarity
	end

	if self.inspectStatsContainer and self.inspectStatTemplate then
		for _, child in ipairs(self.inspectStatsContainer:GetChildren()) do
			if child:IsA("TextLabel") and child ~= self.inspectStatTemplate then
				child:Destroy()
			end
		end
		local function addLine(text: string)
			local line = self.inspectStatTemplate:Clone()
			line.Text = text
			line.Visible = true
			line.Parent = self.inspectStatsContainer
		end
		if def.baseStats then
			for k, v in pairs(def.baseStats) do
				addLine(`${k}: {v}`)
			end
		end
		if def.requirements then
			if def.requirements.level then
				addLine(`Requires Level {def.requirements.level}`)
			end
			if def.requirements.stats then
				for k, v in pairs(def.requirements.stats) do
					addLine(`Requires {k}: {v}`)
				end
			end
		end
		if item and item.meta then
			for k, v in pairs(item.meta) do
				if type(v) ~= "table" then
					addLine(`${k}: {tostring(v)}`)
				end
			end
		end
	end

	-- Action bar (optional)
	if self.inspectActionBar then
		local actions = {}
		if external and external.actions then
			actions = external.actions
		else
			local locked = metaFlag(item and item.meta or nil, "locked") or metaFlag(item and item.meta or nil, "bound")
			if def.equipSlots and location and location.container == "inventory" then
				table.insert(actions, {
					id = "equip",
					label = "Equip",
					enabled = not locked and not metaFlag(item and item.meta or nil, "noEquip"),
					handler = function()
						local slot = pickEquipSlot(def, equip)
						if not slot or not location then
							return
						end
						InventoryClient.requestAction({
							action = "equip",
							fromSlot = location.slot,
							toSlot = slot,
						})
					end,
				})
			end
			if location and location.container == "equipment" then
				table.insert(actions, {
					id = "unequip",
					label = "Unequip",
					enabled = not locked and not metaFlag(item and item.meta or nil, "noUnequip"),
					handler = function()
						if not location then
							return
						end
						InventoryClient.requestAction({
							action = "unequip",
							fromSlot = location.slot,
							toSlot = nil,
						})
					end,
				})
			end
			if def.useAction and item then
				table.insert(actions, {
					id = "use",
					label = "Use",
					enabled = not locked and not metaFlag(item and item.meta or nil, "noUse"),
					handler = function()
						InventoryClient.requestAction({
							action = "use",
							uid = item.uid,
						})
					end,
				})
			end

			if item and location and location.container == "inventory" and not metaFlag(item.meta, "noDrop") then
				table.insert(actions, {
					id = "drop",
					label = "Throw",
					enabled = not locked,
					handler = function()
						InventoryClient.requestAction({
							action = "drop",
							uid = item.uid,
						})
					end,
				})
			end

			-- Stub actions: favorite (disabled by default)
			if SHOW_STUB_ACTIONS then
				table.insert(actions, {
					id = "favorite",
					label = "Favorite",
					handler = function()
						warn("InventoryUIController: favorite action not wired yet")
					end,
				})
			end
		end

		clearChildrenExceptTemplate(self.inspectActionBar, self.inspectActionTemplate)
		if self.inspectActionTemplate and #actions > 0 then
			for _, action in ipairs(actions) do
				local btn = self.inspectActionTemplate:Clone()
				btn.Name = action.id
				btn.Text = action.label
				btn.Visible = true
				btn.Parent = self.inspectActionBar
				local enabled = action.enabled ~= false
				btn.Active = enabled
				btn.AutoButtonColor = enabled
				btn.TextTransparency = enabled and 0 or 0.6
				btn.BackgroundTransparency = enabled and btn.BackgroundTransparency
					or math.min(0.8, btn.BackgroundTransparency + 0.4)
				if enabled then
					btn.MouseButton1Click:Connect(action.handler)
				end
			end
			self.inspectActionBar.Visible = true
		else
			self.inspectActionBar.Visible = false
		end
	end

	self:_applyMenuView()
end

function InventoryUIController:setMenuView(view: MenuView)
	self.currentView = view
	self:_applyMenuView()
end

function InventoryUIController:cycleMenuView(direction: number?): MenuView
	local views: { MenuView } = { "system", "inventory", "equipment" }
	local available: { MenuView } = {}
	for _, view in ipairs(views) do
		if view == "system" then
			table.insert(available, view)
		elseif view == "inventory" and self.inventoryPanel then
			table.insert(available, view)
		elseif view == "equipment" and self.equipmentPanel then
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
	self.currentView = available[nextIdx]
	self:_applyMenuView()
	return self.currentView
end

function InventoryUIController:showInventory()
	self:setMenuView("inventory")
end

function InventoryUIController:showEquipment()
	self:setMenuView("equipment")
end

function InventoryUIController:showBoth()
	-- Legacy shim: default to inventory as primary.
	self:setMenuView("inventory")
end

function InventoryUIController:hideAll()
	local wgm = WorldGUIManager.getInstance()
	self.currentView = "system"
	if self.inventoryPanel then
		wgm:setPanelVisibility("InventoryPanel", false, 0.2, workspace)
	end
	if self.equipmentPanel then
		wgm:setPanelVisibility("EquipmentPanel", false, 0.2, workspace)
	end
	if self.inspectPanelPart then
		wgm:setPanelVisibility("ItemInspectPanel", false, 0.2, workspace)
	end
	self.inspectVisible = false
end

local _instance: InventoryUIController?

local function get()
	if _instance then
		return _instance
	end
	_instance = InventoryUIController.new()
	return _instance
end

local function tryInit()
	local hasInventory = findTemplate("InventoryPanel") ~= nil
	local hasEquipment = findTemplate("EquipmentPanel") ~= nil
	local hasInspect = findTemplate("ItemInspectPanel") ~= nil
	if not (hasInventory or hasEquipment or hasInspect) then
		return nil
	end
	return get()
end

return {
	new = InventoryUIController.new,
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
	setExternalInspect = function(def: ItemTypes.ItemDef, item: ItemTypes.ItemInstance?, actions: { [number]: any }?)
		local inst = get()
		inst.externalInspect = {
			def = def,
			item = item,
			actions = actions,
		}
		inst:updateInspect()
	end,
	clearExternalInspect = function()
		local inst = get()
		inst.externalInspect = nil
		inst:updateInspect()
	end,
}
