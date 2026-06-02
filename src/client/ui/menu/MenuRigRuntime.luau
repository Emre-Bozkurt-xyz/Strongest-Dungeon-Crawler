--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldGUIManager = require(script.Parent.Parent.Parent.WorldGUIManager)
local SharedConfig = require(ReplicatedStorage.Shared.Config)
local DevTuningService = require(script.Parent.Parent.Parent.dev.DevTuningService)

local UIMenuConfig = SharedConfig.UIMenu

type MenuView = "system" | "inventory" | "equipment"
type ModalStateLike = {
	open: boolean,
	view: MenuView,
	primaryPanelId: string?,
	sidePanelIds: { string }?,
}
type MenuStateLike = {
	modal: ModalStateLike,
}

type AnchorBasis = {
	position: Vector3,
	right: Vector3,
	up: Vector3,
	forward: Vector3,
}

type PanelPlacement = {
	offset: Vector3?,
	playerSpaceOffset: Vector3?,
	maxRadius: number?,
}

type PanelSlotConfig = {
	role: string?,
	side: string?,
	order: number?,
}

type LayoutBuckets = {
	primary: string?,
	left: { string },
	right: { string },
}

local MENU_PANEL_IDS = {
	"SystemPanel",
	"InventoryPanel",
	"EquipmentPanel",
	"ItemInspectPanel",
}

local PRIMARY_PANEL_BY_VIEW: { [MenuView]: string } = {
	system = "SystemPanel",
	inventory = "InventoryPanel",
	equipment = "EquipmentPanel",
}

local MenuRigRuntime = {}
MenuRigRuntime.__index = MenuRigRuntime

local _instance = nil

local function tunedString(path: string, fallback: string): string
	local value = DevTuningService.get(path)
	return if type(value) == "string" and value ~= "" then value else fallback
end

local function tunedNumber(path: string, fallback: number): number
	local value = DevTuningService.get(path)
	return if type(value) == "number" then value else fallback
end

local function tunedTable(path: string, fallback: { [string]: any }): { [string]: any }
	local value = DevTuningService.get(path)
	return if type(value) == "table" then value else fallback
end

local function resolveGroupName(): string
	return tunedString("UIMenu.groupName", UIMenuConfig.groupName)
end

local function computeYawAxesFromYaw(yaw: number): (Vector3, Vector3, Vector3)
	local forward = Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
	if forward.Magnitude <= 1e-4 then
		forward = Vector3.new(0, 0, -1)
	else
		forward = forward.Unit
	end
	local up = Vector3.yAxis
	local right = forward:Cross(up)
	if right.Magnitude <= 1e-4 then
		right = Vector3.xAxis
	else
		right = right.Unit
	end
	return right, up, forward
end

local function computeYawAxesFromRoot(root: BasePart): (Vector3, Vector3, Vector3)
	local forward = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if forward.Magnitude <= 1e-4 then
		forward = Vector3.new(0, 0, -1)
	else
		forward = forward.Unit
	end
	local up = Vector3.yAxis
	local right = forward:Cross(up)
	if right.Magnitude <= 1e-4 then
		right = Vector3.xAxis
	else
		right = right.Unit
	end
	return right, up, forward
end

local function transformLocal(right: Vector3, up: Vector3, forward: Vector3, localOffset: Vector3): Vector3
	return right * localOffset.X + up * localOffset.Y + forward * localOffset.Z
end

local function asVector3(value: any, fallback: Vector3): Vector3
	return if typeof(value) == "Vector3" then value else fallback
end

local function clampRadius(anchor: Vector3, desired: Vector3, minRadius: number?, maxRadius: number?): Vector3
	if minRadius == nil and maxRadius == nil then
		return desired
	end
	local offset = desired - anchor
	local distance = offset.Magnitude
	if distance <= 1e-4 then
		return desired
	end
	local targetDistance = distance
	if type(minRadius) == "number" and distance < minRadius then
		targetDistance = minRadius
	end
	if type(maxRadius) == "number" and distance > maxRadius then
		targetDistance = maxRadius
	end
	if targetDistance ~= distance then
		return anchor + offset.Unit * targetDistance
	end
	return desired
end

local function getPanelWidth(part: BasePart): number
	local layoutWidth = part:GetAttribute("LayoutWidth")
	if type(layoutWidth) == "number" and layoutWidth > 0 then
		return layoutWidth
	end
	return math.max(part.Size.X, part.Size.Z)
end

function MenuRigRuntime.new()
	if _instance then
		return _instance
	end

	local self = setmetatable({}, MenuRigRuntime)
	self._modalOpen = false
	self._view = "system" :: MenuView
	self._primaryPanelId = "SystemPanel"
	self._sidePanelIds = {} :: { string }
	self._providerFns = {} :: { [string]: () -> Vector3? }
	self._smoothedAnchorPosition = nil :: Vector3?
	self._lastAnchorUpdateTime = 0

	for _, panelId in ipairs(MENU_PANEL_IDS) do
		self._providerFns[panelId] = function()
			return self:_resolveOverrideTarget(panelId)
		end
	end

	_instance = self
	return self
end

function MenuRigRuntime:_ensureProviders()
	local wgm = WorldGUIManager.peekInstance()
	if not wgm then
		return
	end
	for _, panelId in ipairs(MENU_PANEL_IDS) do
		wgm:setPanelTargetOverrideProvider(panelId, self._providerFns[panelId])
	end
end

function MenuRigRuntime:_getActivePanelIds(): { string }
	if not self._modalOpen then
		return {}
	end

	local ids = {}
	local primary = self._primaryPanelId or PRIMARY_PANEL_BY_VIEW[self._view]
	if type(primary) == "string" and primary ~= "" then
		table.insert(ids, primary)
	end
	for _, panelId in ipairs(self._sidePanelIds) do
		table.insert(ids, panelId)
	end
	return ids
end

function MenuRigRuntime:_getPlayerRoot(): BasePart?
	local player = Players.LocalPlayer
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

function MenuRigRuntime:_resolveAnchorPosition(targetPosition: Vector3): Vector3
	local anchorConfig = tunedTable("UIMenu.anchor", UIMenuConfig.anchor)
	local followSpeed = tunedNumber("UIMenu.anchor.followSpeed", anchorConfig.followSpeed or UIMenuConfig.anchor.followSpeed)
	local snapDistance = tunedNumber(
		"UIMenu.anchor.snapDistance",
		anchorConfig.snapDistance or UIMenuConfig.anchor.snapDistance
	)

	local current = self._smoothedAnchorPosition
	local now = os.clock()
	if current == nil then
		self._smoothedAnchorPosition = targetPosition
		self._lastAnchorUpdateTime = now
		return targetPosition
	end

	if (targetPosition - current).Magnitude >= snapDistance then
		self._smoothedAnchorPosition = targetPosition
		self._lastAnchorUpdateTime = now
		return targetPosition
	end

	local dt = 0
	if self._lastAnchorUpdateTime > 0 then
		dt = math.max(0, now - self._lastAnchorUpdateTime)
	end
	self._lastAnchorUpdateTime = now

	if dt <= 0 then
		return current
	end

	local alpha = 1 - math.exp(-math.max(0.1, followSpeed) * dt)
	local nextPosition = current:Lerp(targetPosition, alpha)
	self._smoothedAnchorPosition = nextPosition
	return nextPosition
end

function MenuRigRuntime:_getPanelSlotConfig(panelId: string): PanelSlotConfig?
	local layout = tunedTable("UIMenu.layout", UIMenuConfig.layout)
	local panelSlots = if type(layout.panelSlots) == "table" then layout.panelSlots else UIMenuConfig.layout.panelSlots
	local config = panelSlots and panelSlots[panelId]
	return if type(config) == "table" then (config :: PanelSlotConfig) else nil
end

function MenuRigRuntime:_getPanelLayoutOrder(panelId: string): number
	local config = self:_getPanelSlotConfig(panelId)
	return if config and type(config.order) == "number" then config.order else 0
end

function MenuRigRuntime:_resolveLayoutBuckets(): LayoutBuckets
	local buckets: LayoutBuckets = {
		primary = nil,
		left = {},
		right = {},
	}
	if not self._modalOpen then
		return buckets
	end

	local primary = self._primaryPanelId or PRIMARY_PANEL_BY_VIEW[self._view]
	if type(primary) == "string" and primary ~= "" then
		buckets.primary = primary
	end

	for _, panelId in ipairs(self._sidePanelIds) do
		local config = self:_getPanelSlotConfig(panelId)
		local side = if config and type(config.side) == "string" then config.side else "right"
		if side == "left" then
			table.insert(buckets.left, panelId)
		else
			table.insert(buckets.right, panelId)
		end
	end

	table.sort(buckets.left, function(a: string, b: string)
		local aOrder = self:_getPanelLayoutOrder(a)
		local bOrder = self:_getPanelLayoutOrder(b)
		if aOrder == bOrder then
			return a < b
		end
		return aOrder < bOrder
	end)
	table.sort(buckets.right, function(a: string, b: string)
		local aOrder = self:_getPanelLayoutOrder(a)
		local bOrder = self:_getPanelLayoutOrder(b)
		if aOrder == bOrder then
			return a < b
		end
		return aOrder < bOrder
	end)

	return buckets
end

function MenuRigRuntime:_getAnchorBasis(): AnchorBasis?
	local root = self:_getPlayerRoot()
	if not root then
		return nil
	end

	local wgm = WorldGUIManager.peekInstance()
	local basisYaw = if wgm then wgm:getGroupBasisYaw(resolveGroupName()) else nil
	local right
	local up
	local forward
	if type(basisYaw) == "number" then
		right, up, forward = computeYawAxesFromYaw(basisYaw)
	else
		right, up, forward = computeYawAxesFromRoot(root)
	end

	local anchorPosition = self:_resolveAnchorPosition(root.Position)

	return {
		position = anchorPosition,
		right = right,
		up = up,
		forward = forward,
	}
end

function MenuRigRuntime:_getPanelConfig(panelId: string): PanelPlacement?
	local wgm = WorldGUIManager.peekInstance()
	if wgm then
		local panelCfg = wgm:getPanelSnapshot(panelId)
		if panelCfg then
			return {
				offset = panelCfg.offset,
				playerSpaceOffset = panelCfg.basePlayerSpaceOffset,
				maxRadius = panelCfg.maxRadius,
			}
		end
	end

	local panels = UIMenuConfig.panels :: any
	local config = panels[panelId]
	return if type(config) == "table" then config else nil
end

function MenuRigRuntime:_getRadiusLimits(panelId: string): (number?, number?)
	local wgm = WorldGUIManager.peekInstance()
	local panelCfg = if wgm then wgm:getPanelSnapshot(panelId) else nil
	local groupParams = if wgm then wgm:getGroupParams(resolveGroupName()) else nil
	local padding = 0
	if panelCfg and type(panelCfg.radiusPadding) == "number" then
		padding = panelCfg.radiusPadding
	elseif groupParams and type(groupParams.radiusPadding) == "number" then
		padding = groupParams.radiusPadding
	end

	local minRadius = nil :: number?
	if panelCfg and type(panelCfg.minRadius) == "number" then
		minRadius = panelCfg.minRadius
	elseif groupParams and type(groupParams.minRadius) == "number" then
		minRadius = groupParams.minRadius
	end
	if type(minRadius) == "number" then
		minRadius += padding
	end

	local maxRadius = nil :: number?
	if panelCfg and type(panelCfg.maxRadius) == "number" then
		maxRadius = panelCfg.maxRadius
	elseif groupParams and type(groupParams.maxRadius) == "number" then
		maxRadius = groupParams.maxRadius
	end

	return minRadius, maxRadius
end

function MenuRigRuntime:_resolveBaseTarget(panelId: string): Vector3?
	local panelCfg = self:_getPanelConfig(panelId)
	local basis = self:_getAnchorBasis()
	if not panelCfg or not basis then
		return nil
	end

	local offset = asVector3(panelCfg.offset, Vector3.zero)
	local playerSpaceOffset = asVector3(panelCfg.playerSpaceOffset, Vector3.zero)
	local desired = basis.position + offset + transformLocal(basis.right, basis.up, basis.forward, playerSpaceOffset)
	local minRadius, maxRadius = self:_getRadiusLimits(panelId)
	return clampRadius(basis.position, desired, minRadius, maxRadius)
end

function MenuRigRuntime:_resolveLayoutLocalOffset(distanceAlongRight: number): Vector3
	local layout = tunedTable("UIMenu.layout", UIMenuConfig.layout)
	local surface = layout.surface or "line"
	if surface == "arc" then
		local radius = math.max(0.1, layout.arcRadius or UIMenuConfig.layout.arcRadius)
		local theta = distanceAlongRight / radius
		local arcDepthSign = layout.arcDepthSign or UIMenuConfig.layout.arcDepthSign or -1
		local arcDepthScale = layout.arcDepthScale or UIMenuConfig.layout.arcDepthScale or 1
		return Vector3.new(
			math.sin(theta) * radius,
			0,
			arcDepthSign * (1 - math.cos(theta)) * radius * arcDepthScale
		)
	end
	return Vector3.new(distanceAlongRight, 0, 0)
end

function MenuRigRuntime:_resolvePanelHalfWidth(panelId: string): number
	local wgm = WorldGUIManager.peekInstance()
	if not wgm then
		return 1
	end
	local width = wgm:getPanelLayoutWidth(panelId)
	if type(width) == "number" and width > 0 then
		return width * 0.5
	end
	return 1
end

function MenuRigRuntime:_resolveSlotOffsets(): { [string]: Vector3 }
	local offsets: { [string]: Vector3 } = {}
	local buckets = self:_resolveLayoutBuckets()
	local primaryPanelId = buckets.primary
	if primaryPanelId == nil then
		return offsets
	end

	local layout = tunedTable("UIMenu.layout", UIMenuConfig.layout)
	local spacing = layout.spacing or UIMenuConfig.layout.spacing or 0
	offsets[primaryPanelId] = Vector3.zero

	local primaryHalfWidth = self:_resolvePanelHalfWidth(primaryPanelId)
	local function resolveSide(panelIds: { string }, direction: number)
		local cursor = 0
		local previousHalfWidth = primaryHalfWidth
		for _, panelId in ipairs(panelIds) do
			local currentHalfWidth = self:_resolvePanelHalfWidth(panelId)
			cursor += previousHalfWidth + currentHalfWidth + spacing
			offsets[panelId] = self:_resolveLayoutLocalOffset(cursor * direction)
			previousHalfWidth = currentHalfWidth
		end
	end

	resolveSide(buckets.left, -1)
	resolveSide(buckets.right, 1)

	return offsets
end

function MenuRigRuntime:_resolveOverrideTarget(panelId: string): Vector3?
	if not self._modalOpen then
		return nil
	end

	local activeIds = self:_getActivePanelIds()
	local isActive = false
	for _, activePanelId in ipairs(activeIds) do
		if activePanelId == panelId then
			isActive = true
			break
		end
	end
	if not isActive then
		return nil
	end

	local baseTarget = self:_resolveBaseTarget(panelId)
	local basis = self:_getAnchorBasis()
	if not baseTarget or not basis then
		return nil
	end

	local slotOffsets = self:_resolveSlotOffsets()
	local localOffset = slotOffsets[panelId]
	if not localOffset then
		return baseTarget
	end

	local target = baseTarget + transformLocal(basis.right, basis.up, basis.forward, localOffset)
	local minRadius, maxRadius = self:_getRadiusLimits(panelId)
	return clampRadius(basis.position, target, minRadius, maxRadius)
end

function MenuRigRuntime:_applyCenterWeights()
	local wgm = WorldGUIManager.peekInstance()
	if not wgm then
		return
	end

	local centerWeights = UIMenuConfig.centerWeights
	local nextWeights = centerWeights.systemView
	if self._view == "inventory" then
		nextWeights = centerWeights.inventoryView
	elseif self._view == "equipment" then
		nextWeights = centerWeights.equipmentView
	end

	wgm:setGroupParams(resolveGroupName(), {
		centerWeights = tunedTable(`UIMenu.centerWeights.{self._view}View`, nextWeights),
	})
end

function MenuRigRuntime:applyMenuState(state: MenuStateLike)
	local wasOpen = self._modalOpen
	self._modalOpen = state.modal.open
	self._view = state.modal.view
	self._primaryPanelId = state.modal.primaryPanelId or PRIMARY_PANEL_BY_VIEW[state.modal.view]
	self._sidePanelIds = if type(state.modal.sidePanelIds) == "table" then table.clone(state.modal.sidePanelIds) else {}
	if not self._modalOpen then
		self._smoothedAnchorPosition = nil
		self._lastAnchorUpdateTime = 0
	elseif not wasOpen then
		local root = self:_getPlayerRoot()
		if root then
			self._smoothedAnchorPosition = root.Position
			self._lastAnchorUpdateTime = os.clock()
		end
	end
	self:_ensureProviders()
	self:_applyCenterWeights()
end

function MenuRigRuntime:isOpen(): boolean
	return self._modalOpen
end

function MenuRigRuntime:getBasisYaw(): number?
	local wgm = WorldGUIManager.peekInstance()
	if wgm then
		local basisYaw = wgm:getGroupBasisYaw(resolveGroupName())
		if type(basisYaw) == "number" then
			return basisYaw
		end
	end

	local root = self:_getPlayerRoot()
	if not root then
		return nil
	end

	local forward = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if forward.Magnitude <= 1e-4 then
		return nil
	end
	forward = forward.Unit
	return math.atan2(-forward.X, -forward.Z)
end

function MenuRigRuntime:getPrimaryPanelId(): string
	return self._primaryPanelId
end

function MenuRigRuntime:getFocusPoint(): Vector3?
	if not self._modalOpen then
		return nil
	end

	self:_ensureProviders()
	local wgm = WorldGUIManager.peekInstance()
	if not wgm then
		return nil
	end

	local groupParams = wgm:getGroupParams(resolveGroupName())
	local centerWeights = if groupParams and type(groupParams.centerWeights) == "table" then groupParams.centerWeights else nil

	local sum = Vector3.zero
	local weightSum = 0
	for _, panelId in ipairs(self:_getActivePanelIds()) do
		local target = self:_resolveOverrideTarget(panelId)
		if target then
			local weight = 1
			if centerWeights then
				local weighted = centerWeights[panelId] or centerWeights._default
				if type(weighted) == "number" then
					weight = weighted
				end
			end
			sum += target * weight
			weightSum += weight
		end
	end

	if weightSum > 0 then
		return sum / weightSum
	end

	return self:_resolveOverrideTarget(self:getPrimaryPanelId())
end

function MenuRigRuntime.get()
	return _instance or MenuRigRuntime.new()
end

return MenuRigRuntime
