--!strict
-- Owns ItemInspectPanel template instantiation, data rendering, actions, and visibility.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldGUIManager = require(script.Parent.Parent.Parent.WorldGUIManager)
local InventoryClient = require(script.Parent.Parent.Parent.Inventory.InventoryClient)
local Registry = require(ReplicatedStorage.Shared.items.Registry)
local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)
local EquipmentDefUtils = require(ReplicatedStorage.Shared.items.EquipmentDefUtils)
local Config = require(ReplicatedStorage.Shared.Config)
local DevTuningService = require(script.Parent.Parent.Parent.dev.DevTuningService)
local PanelTemplateResolver = require(script.Parent.PanelTemplateResolver)
local PanelBinder = require(script.Parent.PanelBinder)
local SlotVisuals = require(script.Parent.SlotVisuals)

local ItemInspectRuntime = {}
ItemInspectRuntime.__index = ItemInspectRuntime

export type Config = {
	groupName: string,
	offset: Vector3,
	playerSpaceOffset: Vector3,
	faceBlend: number,
	maxRadius: number,
}

local PANEL_NAME = "ItemInspectPanel"
local UIMenuConfig = Config.UIMenu
local ItemInspectConfig = Config.ItemInspect

type StatLineStyle = {
	sizeScale: number?,
	color: Color3?,
	transparency: number?,
}

type InspectStateLike = {
	source: string,
	payload: any,
}

local function tunedTable(path: string, fallback: { [string]: any }): { [string]: any }
	local value = DevTuningService.get(path)
	return if type(value) == "table" then value else fallback
end

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

local function joinChildDescriptors(root: Instance): string
	local items = {}
	for _, child in ipairs(root:GetChildren()) do
		table.insert(items, `{child.Name}:{child.ClassName}`)
	end
	table.sort(items)
	return table.concat(items, ", ")
end

local function clearChildrenExceptTemplate(container: Instance, template: Instance?)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("TextButton") and child ~= template then
			child:Destroy()
		end
	end
end

local function metaFlag(meta: { [string]: any }?, key: string): boolean
	if not meta then
		return false
	end
	return meta[key] == true
end

local function pickEquipSlot(def: ItemTypes.ItemDef, equip: ItemTypes.EquipmentState?): string?
	local equipSlots = EquipmentDefUtils.getEquipSlots(def)
	if not equipSlots or #equipSlots == 0 then
		return nil
	end
	if equip then
		for _, slot in ipairs(equipSlots) do
			if equip.slots[slot] == nil then
				return slot
			end
		end
	end
	return equipSlots[1]
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

local function isEquipmentItem(def: ItemTypes.ItemDef): boolean
	return EquipmentDefUtils.isEquipment(def)
end

local function formatNumber(value: number): string
	if math.abs(value - math.floor(value)) < 0.0001 then
		return tostring(math.floor(value))
	end
	return string.format("%.2f", value)
end

local function formatModifier(mod: ItemTypes.ModifierEntry): string
	local sign = if mod.value >= 0 then "+" else ""
	local value = formatNumber(mod.value)
	if mod.kind == "percent" then
		return `{sign}{formatNumber(mod.value * 100)}% {mod.target}`
	end
	if mod.kind == "percent_of_stat" then
		return `{sign}{formatNumber(mod.value * 100)}% of {mod.target}`
	end
	return `{sign}{value} {mod.target}`
end

local function findAffixModifiers(item: ItemTypes.ItemInstance?): { ItemTypes.ModifierEntry }
	local results: { ItemTypes.ModifierEntry } = {}
	local affixes = item and item.meta and item.meta.affixes or nil
	if type(affixes) ~= "table" then
		return results
	end
	for _, entry in ipairs(affixes) do
		if type(entry) == "table" then
			if entry.modifiers and type(entry.modifiers) == "table" then
				for _, mod in ipairs(entry.modifiers) do
					if type(mod) == "table" and type(mod.target) == "string" and type(mod.value) == "number" then
						table.insert(results, mod :: ItemTypes.ModifierEntry)
					end
				end
			elseif type(entry.target) == "string" and type(entry.value) == "number" then
				table.insert(results, entry :: ItemTypes.ModifierEntry)
			end
		end
	end
	return results
end

function ItemInspectRuntime.new(config: Config)
	local self = setmetatable({}, ItemInspectRuntime)
	self._wgm = WorldGUIManager.getInstance()
	self._panelPart = nil :: BasePart?
	self._panel = nil :: Frame?
	self._icon = nil :: ImageLabel?
	self._nameLabel = nil :: TextLabel?
	self._rarityLabel = nil :: TextLabel?
	self._statsContainer = nil :: ScrollingFrame?
	self._statTemplate = nil :: TextLabel?
	self._actionBar = nil :: Frame?
	self._actionTemplate = nil :: TextButton?
	self._inspectState = nil :: InspectStateLike?
	self._didLogMissingBindings = false
	self._config = config
	self._tuneConnUIMenu = nil :: (() -> ())?
	self._tuneConnInspect = nil :: (() -> ())?
	self._inventoryConn = nil :: (() -> ())?

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
			playerOffsetMode = UIMenuConfig.panels.ItemInspectPanel.playerOffsetMode,
			maxRadius = config.maxRadius,
		})
		self._wgm:setPanelVisibility(PANEL_NAME, false, 0, workspace)
		local partBinder = PanelBinder.new(self._panelPart)
		self._panel = partBinder:find({ "Root" }, "Frame") :: Frame?
		if self._panel then
			local panelBinder = PanelBinder.new(self._panel)
			self._icon = panelBinder:find({ "Icon" }, "ImageLabel") :: ImageLabel?
			self._nameLabel = panelBinder:find({ "NameLabel", "Title" }, "TextLabel") :: TextLabel?
			self._rarityLabel = panelBinder:find({ "RarityLabel" }, "TextLabel") :: TextLabel?
			self._statsContainer = panelBinder:find({ "InfoContainer" }, "ScrollingFrame") :: ScrollingFrame?
			self._statTemplate = if self._statsContainer
				then (PanelBinder.new(self._statsContainer):find({ "ContentTemplate" }, "TextLabel") :: TextLabel?)
				else nil
			if self._statTemplate then
				self._statTemplate.Visible = false
			end
			self._actionBar = panelBinder:find({ "ActionBar" }, "Frame") :: Frame?
			if self._actionBar then
				self._actionTemplate =
					PanelBinder.new(self._actionBar):find({ "ActionButtonTemplate" }, "TextButton") :: TextButton?
				if self._actionTemplate then
					self._actionTemplate.Visible = false
				end
			end
			if not self._statsContainer then
				warn(
					`ItemInspectRuntime[{PANEL_NAME}]: missing InfoContainer:ScrollingFrame under Root. Root children: {joinChildDescriptors(self._panel)}`
				)
			elseif not self._statTemplate then
				warn(
					`ItemInspectRuntime[{PANEL_NAME}]: missing ContentTemplate:TextLabel under InfoContainer:ScrollingFrame. InfoContainer children: {joinChildDescriptors(self._statsContainer)}`
				)
			end
		else
			warn(`ItemInspectRuntime[{PANEL_NAME}]: missing Root frame under panel part {self._panelPart:GetFullName()}`)
		end
	end

	self._tuneConnUIMenu = DevTuningService.subscribe("UIMenu", function()
		self:_applyUIMenuTuning()
	end)
	self._tuneConnInspect = DevTuningService.subscribe("ItemInspect", function()
		self:refresh()
	end)
	self._inventoryConn = InventoryClient.onChanged(function()
		self:refresh()
	end)
	self:_applyUIMenuTuning()

	return self
end

function ItemInspectRuntime:isAvailable(): boolean
	return self._panelPart ~= nil
end

function ItemInspectRuntime:setInspectState(inspectState: InspectStateLike?)
	self._inspectState = inspectState
	self:refresh()
end

function ItemInspectRuntime:setVisible(visible: boolean, transition: number?)
	if not self._panelPart then
		return
	end
	self._wgm:setPanelVisibility(PANEL_NAME, visible, transition or 0.2, workspace)
end

function ItemInspectRuntime:resetFollow()
	if not self._panelPart then
		return
	end
	self._wgm:setPanelFollowModeLock(PANEL_NAME, false)
	self._wgm:setPanelFollowTarget(PANEL_NAME, nil)
	self._wgm:setPanelFollowMode(PANEL_NAME, "player")
	self._wgm:setPanelPlayerSpaceOffset(PANEL_NAME, self._config.playerSpaceOffset)
end

function ItemInspectRuntime:_applyUIMenuTuning()
	if not self._panelPart then
		return
	end

	self._config.groupName = tunedString("UIMenu.groupName", UIMenuConfig.groupName)
	self._config.offset = tunedVector3("UIMenu.panels.ItemInspectPanel.offset", UIMenuConfig.panels.ItemInspectPanel.offset)
	self._config.playerSpaceOffset = tunedVector3(
		"UIMenu.panels.ItemInspectPanel.playerSpaceOffset",
		UIMenuConfig.panels.ItemInspectPanel.playerSpaceOffset
	)
	self._config.faceBlend = tunedNumber("UIMenu.panels.ItemInspectPanel.faceBlend", UIMenuConfig.panels.ItemInspectPanel.faceBlend)
	self._config.maxRadius = tunedNumber("UIMenu.panels.ItemInspectPanel.maxRadius", UIMenuConfig.panels.ItemInspectPanel.maxRadius)

	local wgm = self._wgm
	wgm:updatePanel(PANEL_NAME, {
		group = self._config.groupName,
		offset = self._config.offset,
		playerSpaceOffset = self._config.playerSpaceOffset,
		faceBlend = self._config.faceBlend,
		maxRadius = self._config.maxRadius,
		playerOffsetMode = tunedString(
			"UIMenu.panels.ItemInspectPanel.playerOffsetMode",
			UIMenuConfig.panels.ItemInspectPanel.playerOffsetMode
		),
	})
end

function ItemInspectRuntime:refresh()
	if not self._panel then
		return
	end
	local items = InventoryClient.getItems()
	local inv = InventoryClient.getInventory()
	local equip = InventoryClient.getEquipment()
	local inspect = self._inspectState
	local payload = inspect and inspect.payload or nil
	local uid = if type(payload) == "table" and type(payload.uid) == "string" then payload.uid else nil
	local item = uid and items[uid] or nil
	local def = item and Registry.get(item.itemId) or nil
	local location = uid and getItemLocation(uid, inv, equip) or nil
	local detailStyles = tunedTable("ItemInspect.detailStyles", ItemInspectConfig.detailStyles)
	local excludedMetaKeys = tunedTable("ItemInspect.excludedMetaKeys", ItemInspectConfig.excludedMetaKeys)

	if not def then
		if self._icon then
			self._icon.Visible = false
		end
		if self._nameLabel then
			self._nameLabel.Text = ""
		end
		if self._rarityLabel then
			self._rarityLabel.Text = ""
		end
		if self._statsContainer and self._statTemplate then
			for _, child in ipairs(self._statsContainer:GetChildren()) do
				if child:IsA("TextLabel") and child ~= self._statTemplate then
					child:Destroy()
				end
			end
		end
		if self._actionBar then
			clearChildrenExceptTemplate(self._actionBar, self._actionTemplate)
			self._actionBar.Visible = false
		end
		return
	end

	if self._icon then
		self._icon.Image = def.icon or ""
		self._icon.Visible = self._icon.Image ~= ""
	end
	if self._nameLabel then
		local displayName = if item and item.meta and type(item.meta.displayName) == "string" then item.meta.displayName else def.name
		self._nameLabel.Text = displayName
	end
	if self._rarityLabel then
		self._rarityLabel.Text = SlotVisuals.resolveItemRarity(item, def)
	end

	if self._statsContainer and self._statTemplate then
		for _, child in ipairs(self._statsContainer:GetChildren()) do
			if child:IsA("TextLabel") and child ~= self._statTemplate then
				child:Destroy()
			end
		end
		local lineCount = 0
		local function addLine(text: string, style: StatLineStyle?)
			local line = self._statTemplate:Clone()
			line.Text = text
			if style then
				if style.sizeScale then
					line.TextSize = math.max(1, line.TextSize * style.sizeScale)
				end
				if style.color then
					line.TextColor3 = style.color
				end
				if style.transparency then
					line.TextTransparency = style.transparency
				end
			end
			line.Visible = true
			line.Parent = self._statsContainer
			lineCount += 1
		end

		if isEquipmentItem(def) then
			local requirements = EquipmentDefUtils.getRequirements(def)
			if requirements then
				addLine("Requirements", detailStyles.sectionHeading)
				if requirements.level then
					addLine(`Level {requirements.level}`, detailStyles.requirementLine)
				end
				if requirements.stats then
					for k, v in pairs(requirements.stats) do
						addLine(`${k}: {formatNumber(v)}`, detailStyles.requirementLine)
					end
				end
				if requirements.attributes then
					for k, v in pairs(requirements.attributes) do
						addLine(`${k}: {formatNumber(v)}`, detailStyles.requirementLine)
					end
				end
			end
			local baseModifiers = EquipmentDefUtils.getBaseModifiers(def, item)
			if #baseModifiers > 0 then
				addLine("Base Stats", detailStyles.sectionHeading)
				for _, entry in ipairs(baseModifiers) do
					addLine(formatModifier(entry), detailStyles.baseStatLine)
				end
			end
			local affixMods = findAffixModifiers(item)
			if #affixMods > 0 then
				addLine("Affix Mods", detailStyles.sectionHeading)
				for _, mod in ipairs(affixMods) do
					addLine(formatModifier(mod), detailStyles.affixLine)
				end
			end
		else
			for _, entry in ipairs(EquipmentDefUtils.getBaseModifiers(def, item)) do
				addLine(formatModifier(entry))
			end
			if def.baseStats then
				for k, v in pairs(def.baseStats) do
					addLine(`${k}: {formatNumber(v)}`)
				end
			end
			local requirements = EquipmentDefUtils.getRequirements(def)
			if requirements then
				if requirements.level then
					addLine(`Requires Level {requirements.level}`)
				end
				if requirements.stats then
					for k, v in pairs(requirements.stats) do
						addLine(`Requires {k}: {formatNumber(v)}`)
					end
				end
				if requirements.attributes then
					for k, v in pairs(requirements.attributes) do
						addLine(`Requires {k}: {formatNumber(v)}`)
					end
				end
			end
		end
		if item and item.meta then
			for k, v in pairs(item.meta) do
				if type(v) ~= "table" and not excludedMetaKeys[k] then
					addLine(`${k}: {tostring(v)}`)
				end
			end
		end
		if isEquipmentItem(def) and lineCount == 0 then
			warn(
				`ItemInspectRuntime[{PANEL_NAME}]: built 0 stat lines for equipment {def.id}. baseModifiers={tostring(item and item.meta and item.meta.baseModifiers ~= nil)} requirements={tostring(EquipmentDefUtils.getRequirements(def) ~= nil)} affixes={tostring(item and item.meta and item.meta.affixes ~= nil)}`
			)
		end
	elseif isEquipmentItem(def) and (not self._didLogMissingBindings) then
		self._didLogMissingBindings = true
		warn(
			`ItemInspectRuntime[{PANEL_NAME}]: cannot render equipment details because InfoContainer/ContentTemplate binding is missing. panel={if self._panel then self._panel:GetFullName() else "nil"}`
		)
	end

	if self._actionBar then
		local actions = {}
		local locked = metaFlag(item and item.meta or nil, "locked") or metaFlag(item and item.meta or nil, "bound")
		if EquipmentDefUtils.getEquipSlots(def) and location and location.container == "inventory" then
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

		clearChildrenExceptTemplate(self._actionBar, self._actionTemplate)
		if self._actionTemplate and #actions > 0 then
			for _, action in ipairs(actions) do
				local btn = self._actionTemplate:Clone()
				btn.Name = action.id
				btn.Text = action.label
				btn.Visible = true
				btn.Parent = self._actionBar
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
			self._actionBar.Visible = true
		else
			self._actionBar.Visible = false
		end
	end
end

function ItemInspectRuntime:destroy()
	if self._tuneConnUIMenu then
		self._tuneConnUIMenu()
		self._tuneConnUIMenu = nil
	end
	if self._tuneConnInspect then
		self._tuneConnInspect()
		self._tuneConnInspect = nil
	end
	if self._inventoryConn then
		self._inventoryConn()
		self._inventoryConn = nil
	end
	if self._panelPart then
		self._panelPart:Destroy()
		self._panelPart = nil
	end
end

local DEFAULT_CONFIG: Config = {
	groupName = UIMenuConfig.groupName,
	offset = UIMenuConfig.panels.ItemInspectPanel.offset,
	playerSpaceOffset = UIMenuConfig.panels.ItemInspectPanel.playerSpaceOffset,
	faceBlend = UIMenuConfig.panels.ItemInspectPanel.faceBlend,
	maxRadius = UIMenuConfig.panels.ItemInspectPanel.maxRadius,
}

local _instance: any = nil

local function getOrCreate()
	if _instance then
		return _instance
	end
	_instance = ItemInspectRuntime.new(DEFAULT_CONFIG)
	if not _instance:isAvailable() then
		_instance = nil
		return nil
	end
	return _instance
end

return {
	new = ItemInspectRuntime.new,
	get = getOrCreate,
	tryInit = getOrCreate,
}
