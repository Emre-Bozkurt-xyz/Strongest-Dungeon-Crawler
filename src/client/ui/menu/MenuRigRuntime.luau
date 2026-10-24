--!strict
-- The menu stage: where every menu panel sits and where the camera watches from, solved from the
-- character's position and the yaw it had when the menu opened.
--
-- The primary panel is placed for the character -- ahead of it and to one side, turned mostly toward
-- its head -- and side panels line up beside it in the same plane. The camera takes its own seat in
-- the character's frame and looks where its pose says, not at the panel. Neither reads the other's
-- live, smoothed position, so there is no feedback loop to jitter (docs/tasks/menu-rig-runtime.md,
-- rule 3), and composition is tuned by moving the two poses in UIMenuConfig.stage.
--
-- WorldGUIManager still moves the parts. It receives a full CFrame per panel through its target
-- override providers and only smooths toward it. See docs/tasks/menu-staging.md.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local WorldGUIManager = require(script.Parent.Parent.Parent.WorldGUIManager)
local UIMenuConfig = require(ReplicatedStorage.Shared.Config.UIMenuConfig)
local DevTuningService = require(script.Parent.Parent.Parent.dev.DevTuningService)

local StageConfig = UIMenuConfig.stage

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

type Solve = {
	camera: CFrame,
	panels: { [string]: CFrame },
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

-- Above the HumanoidRootPart. The head is what a panel turns toward; the wall checks start there so a
-- low obstacle in front of the feet does not count as a wall between the character and the camera.
local HEAD_HEIGHT = 1.5

local MenuRigRuntime = {}
MenuRigRuntime.__index = MenuRigRuntime

local _instance = nil

local function tunedTable(path: string, fallback: { [string]: any }): { [string]: any }
	local value = DevTuningService.get(path)
	return if type(value) == "table" then value else fallback
end

local function getViewStage(view: MenuView): UIMenuConfig.ViewStage
	local views = tunedTable("UIMenu.stage.views", StageConfig.views)
	return (views[view] or StageConfig.views[view]) :: UIMenuConfig.ViewStage
end

local function getPlayerRoot(): BasePart?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function flatYaw(root: BasePart): number
	local look = root.CFrame.LookVector
	return math.atan2(-look.X, -look.Z)
end

-- `side` is 1 for the authored pose and -1 for its mirror on the character's other side.
local function cameraPose(basis: CFrame, pose: UIMenuConfig.CameraPose, side: number): CFrame
	return basis
		* CFrame.new(pose.right * side, pose.up, pose.back)
		* CFrame.Angles(0, -math.rad(pose.yaw) * side, 0)
		* CFrame.Angles(math.rad(pose.pitch), 0, 0)
end

local function primaryPosition(basis: CFrame, pose: UIMenuConfig.PanelPose, side: number): Vector3
	return (basis * CFrame.new(pose.right * side, pose.up, -pose.ahead)).Position
end

local function wallParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local character = Players.LocalPlayer.Character
	params.FilterDescendantsInstances = if character then { character } else {}
	-- Panels, loot and other non-colliding parts are not walls.
	params.RespectCanCollide = true
	return params
end

-- How far toward `to` the way is clear, or nil when nothing is in the way.
local function obstruction(from: Vector3, to: Vector3): number?
	local result = Workspace:Raycast(from, to - from, wallParams())
	return if result then result.Distance else nil
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
	self._basisYaw = nil :: number?
	-- Which side of the character the stage is built on. Chosen when the menu opens or the view
	-- changes, not per frame, so walking along a wall cannot make it flip back and forth.
	self._side = 1
	-- World-space studs, declared up front by UIRuntime. Read from the registry rather than the live
	-- parts because a side panel's part does not exist until it is first shown.
	self._panelSizes = {} :: { [string]: Vector2 }
	self._providerFns = {} :: { [string]: () -> CFrame? }

	for _, panelId in ipairs(MENU_PANEL_IDS) do
		self._providerFns[panelId] = function()
			local solve = self:_solve()
			return if solve then solve.panels[panelId] else nil
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

function MenuRigRuntime:_basis(root: BasePart): CFrame
	return CFrame.new(root.Position) * CFrame.Angles(0, self._basisYaw or flatYaw(root), 0)
end

-- How far the composition can reach outward from the primary's centre: its half width plus every
-- side panel that could open on the outer side. Counted whether or not they are showing, so a panel
-- opened later does not land in the wall the check was meant to avoid.
function MenuRigRuntime:_outerReach(): number
	local reach = (self._panelSizes[self._primaryPanelId] or Vector2.zero).X / 2
	for panelId, slot in pairs(UIMenuConfig.sideSlots :: any) do
		if slot.side == "right" then
			reach += StageConfig.spacing + (self._panelSizes[panelId] or Vector2.zero).X
		end
	end
	return reach
end

-- The authored side unless a wall blocks the camera's seat or the panels' reach; then the mirror.
function MenuRigRuntime:_chooseSide()
	local root = getPlayerRoot()
	if not root then
		return
	end
	local basis = self:_basis(root)
	local stage = getViewStage(self._view)
	local head = root.Position + Vector3.yAxis * HEAD_HEIGHT
	local reach = self:_outerReach()
	for _, side in ipairs({ 1, -1 }) do
		local seatClear = not obstruction(head, cameraPose(basis, stage.camera, side).Position)
		local outerEdge = primaryPosition(basis, stage.panel, side) + basis.RightVector * (reach * side)
		local panelClear = not obstruction(head, outerEdge)
		if seatClear and panelClear then
			self._side = side
			return
		end
	end
	-- Walled in on both sides: keep the authored side and let the camera be pulled in.
	self._side = 1
end

function MenuRigRuntime:_solveCamera(root: BasePart, basis: CFrame, stage: UIMenuConfig.ViewStage): CFrame
	local pose = cameraPose(basis, stage.camera, self._side)
	local head = root.Position + Vector3.yAxis * HEAD_HEIGHT
	local blockedAt = obstruction(head, pose.Position)
	if not blockedAt then
		return pose
	end
	local direction = (pose.Position - head).Unit
	local position = head + direction * math.max(0, blockedAt - StageConfig.wallClearance)
	return pose.Rotation + position
end

function MenuRigRuntime:_sideBuckets(): ({ string }, { string })
	local left: { string } = {}
	local right: { string } = {}
	for _, panelId in ipairs(self._sidePanelIds) do
		local slot = (UIMenuConfig.sideSlots :: any)[panelId]
		-- Mirrored with the stage: when a wall moved everything to the character's other side, a side
		-- panel on its authored side would now be the one nearest the wall.
		local authoredLeft = slot ~= nil and slot.side == "left"
		if authoredLeft == (self._side == 1) then
			table.insert(left, panelId)
		else
			table.insert(right, panelId)
		end
	end
	local function byOrder(a: string, b: string): boolean
		local aSlot = (UIMenuConfig.sideSlots :: any)[a]
		local bSlot = (UIMenuConfig.sideSlots :: any)[b]
		local aOrder = if aSlot then aSlot.order else 0
		local bOrder = if bSlot then bSlot.order else 0
		if aOrder == bOrder then
			return a < b
		end
		return aOrder < bOrder
	end
	table.sort(left, byOrder)
	table.sort(right, byOrder)
	return left, right
end

function MenuRigRuntime:_solve(): Solve?
	if not self._modalOpen then
		return nil
	end
	local root = getPlayerRoot()
	if not root then
		return nil
	end

	local stage = getViewStage(self._view)
	local basis = self:_basis(root)
	local camera = self:_solveCamera(root, basis, stage)

	local head = root.Position + Vector3.yAxis * HEAD_HEIGHT
	local position = primaryPosition(basis, stage.panel, self._side)
	local faceAt = head:Lerp(camera.Position, stage.panel.faceCamera)
	local panelPose = stage.panel
	local primary = CFrame.lookAt(position, Vector3.new(faceAt.X, position.Y, faceAt.Z))
		* CFrame.Angles(0, math.rad(panelPose.turn or 0) * self._side, 0)
		* CFrame.Angles(math.rad(panelPose.tilt or 0), 0, 0)
	local panels: { [string]: CFrame } = { [self._primaryPanelId] = primary }

	-- Side panels continue the primary's plane outward. The panel faces its reader, so the reader's
	-- right is the part's -X.
	local spacing = StageConfig.spacing
	local primaryHalf = (self._panelSizes[self._primaryPanelId] or Vector2.zero).X / 2
	local left, right = self:_sideBuckets()
	for _, bucket in ipairs({ { ids = right, direction = -1 }, { ids = left, direction = 1 } }) do
		local cursor = primaryHalf
		for _, panelId in ipairs(bucket.ids) do
			local width = (self._panelSizes[panelId] or Vector2.zero).X
			cursor += spacing + width / 2
			panels[panelId] = primary * CFrame.new(cursor * bucket.direction, 0, 0)
			cursor += width / 2
		end
	end

	return { camera = camera, panels = panels }
end

function MenuRigRuntime:applyMenuState(state: MenuStateLike)
	local wasOpen = self._modalOpen
	local previousView = self._view
	self._modalOpen = state.modal.open
	self._view = state.modal.view
	self._primaryPanelId = state.modal.primaryPanelId or PRIMARY_PANEL_BY_VIEW[state.modal.view]
	self._sidePanelIds = if type(state.modal.sidePanelIds) == "table" then table.clone(state.modal.sidePanelIds) else {}

	if not self._modalOpen then
		self._basisYaw = nil
	elseif not wasOpen then
		local root = getPlayerRoot()
		self._basisYaw = if root then flatYaw(root) else nil
		self:_chooseSide()
	elseif previousView ~= self._view then
		self:_chooseSide()
	end

	self:_ensureProviders()
end

function MenuRigRuntime:setPanelSize(panelId: string, width: number, height: number)
	self._panelSizes[panelId] = Vector2.new(width, height)
end

function MenuRigRuntime:isOpen(): boolean
	return self._modalOpen
end

function MenuRigRuntime:getPrimaryPanelId(): string
	return self._primaryPanelId
end

-- Where the camera belongs while the menu is open, and how it renders. Read every frame by the menu
-- camera modifier, so tuning any of it applies live.
function MenuRigRuntime:getCameraPose(): {
	cframe: CFrame,
	fov: number,
	duration: number,
	releaseDuration: number,
	key: string,
}?
	local solve = self:_solve()
	if not solve then
		return nil
	end
	local move = DevTuningService.get("UIMenu.stage.cameraMove")
	local release = DevTuningService.get("UIMenu.stage.cameraRelease")
	return {
		cframe = solve.camera,
		fov = getViewStage(self._view).camera.fov,
		duration = if type(move) == "number" then move else StageConfig.cameraMove,
		releaseDuration = if type(release) == "number" then release else StageConfig.cameraRelease,
		-- Each view is its own move; switching restarts the camera's travel from where it is.
		key = self._view,
	}
end

MenuRigRuntime.MENU_PANEL_IDS = MENU_PANEL_IDS

function MenuRigRuntime.get()
	return _instance or MenuRigRuntime.new()
end

return MenuRigRuntime
