--!strict
-- The menu stage: one solve that yields both where the camera stands and where every menu panel
-- sits, from the character's position and the yaw it had when the menu opened.
--
-- The camera pose comes first and the panels are fitted to it -- square to the camera, at whatever
-- distance makes the composition fill a set share of the view. Neither side reads the other's live,
-- smoothed position, so there is no feedback loop to jitter (docs/tasks/menu-rig-runtime.md, rule 3),
-- and a panel occupies the same share of the frame on any screen shape.
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

-- Where the wall check starts: roughly the character's shoulder, so a low obstacle in front of the
-- feet does not count as a wall between the character and the camera.
local SHOULDER_HEIGHT = 1.0

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

-- `side` is 1 for the configured pose and -1 for its mirror on the character's other side.
local function poseFromBasis(basis: CFrame, pose: UIMenuConfig.CameraPose, side: number): CFrame
	local position = (basis * CFrame.new(pose.right * side, pose.up, pose.back)).Position
	local facing = basis * CFrame.Angles(0, math.rad(pose.turn) * side, 0)
	return CFrame.lookAt(position, position + facing.LookVector)
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

-- How far toward `to` the camera can go before hitting something, or nil when the way is clear.
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
	-- Which side of the character the camera stands on. Chosen when the menu opens or the view
	-- changes, not per frame, so walking along a wall cannot make the camera flip back and forth.
	self._side = 1
	-- Studs, declared up front by UIRuntime. Read from the registry rather than the live parts
	-- because a side panel's part does not exist until it is first shown, and a reserved slot has to
	-- be the right size before then.
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

function MenuRigRuntime.getFov(): number
	local tuned = DevTuningService.get("UIMenu.stage.fov")
	return if type(tuned) == "number" then tuned else StageConfig.fov
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

function MenuRigRuntime:_chooseSide()
	local root = getPlayerRoot()
	if not root then
		return
	end
	local basis = self:_basis(root)
	local pose = getViewStage(self._view).camera
	local shoulder = root.Position + Vector3.yAxis * SHOULDER_HEIGHT
	for _, side in ipairs({ 1, -1 }) do
		if not obstruction(shoulder, poseFromBasis(basis, pose, side).Position) then
			self._side = side
			return
		end
	end
	-- Walled in on both sides: keep the preferred side and let the camera be pulled in.
	self._side = 1
end

function MenuRigRuntime:_solveCamera(root: BasePart, stage: UIMenuConfig.ViewStage): CFrame
	local pose = poseFromBasis(self:_basis(root), stage.camera, self._side)
	local shoulder = root.Position + Vector3.yAxis * SHOULDER_HEIGHT
	local blockedAt = obstruction(shoulder, pose.Position)
	if not blockedAt then
		return pose
	end
	local direction = (pose.Position - shoulder).Unit
	local position = shoulder + direction * math.max(0, blockedAt - StageConfig.wallClearance)
	return CFrame.lookAt(position, position + pose.LookVector)
end

-- Left-to-right order of the composition: left side panels, the primary, then right side panels.
-- Reserved panels are included whether or not they are showing, so the layout does not shift when
-- one appears.
function MenuRigRuntime:_composition(stage: UIMenuConfig.ViewStage): { string }
	local present: { [string]: boolean } = {}
	for _, panelId in ipairs(self._sidePanelIds) do
		present[panelId] = true
	end
	for _, panelId in ipairs(stage.reserve) do
		present[panelId] = true
	end

	local left: { string } = {}
	local right: { string } = {}
	for panelId in pairs(present) do
		local slot = (UIMenuConfig.sideSlots :: any)[panelId]
		-- Mirrored with the camera: when a wall pushed the camera to the character's left, the wall
		-- is now on the composition's authored side, and a side panel placed there would sink into it.
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
	-- Left panels are ordered outward from the primary, so they are reversed into screen order.
	table.sort(left, function(a, b)
		return byOrder(b, a)
	end)
	table.sort(right, byOrder)

	local ordered = left
	table.insert(ordered, self._primaryPanelId)
	for _, panelId in ipairs(right) do
		table.insert(ordered, panelId)
	end
	return ordered
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
	local camera = self:_solveCamera(root, stage)

	local ids = self:_composition(stage)
	local widths: { number } = {}
	local totalWidth = 0
	local maxHeight = 0
	for index, panelId in ipairs(ids) do
		local size = self._panelSizes[panelId] or Vector2.zero
		widths[index] = size.X
		totalWidth += size.X
		maxHeight = math.max(maxHeight, size.Y)
	end
	totalWidth += StageConfig.spacing * math.max(0, #ids - 1)
	if totalWidth <= 0 then
		return { camera = camera, panels = {} }
	end

	-- Fit by width, or by height when the composition is tall for this screen shape, whichever puts
	-- the panels further away.
	local vfov = math.rad(MenuRigRuntime.getFov())
	local viewport = Workspace.CurrentCamera.ViewportSize
	local aspect = if viewport.Y > 0 then viewport.X / viewport.Y else 16 / 9
	local halfTanV = math.tan(vfov / 2)
	local halfTanH = halfTanV * aspect
	local distance = math.max(
		(totalWidth / stage.fill) / (2 * halfTanH),
		(maxHeight / StageConfig.maxHeightFill) / (2 * halfTanV)
	)

	-- Panels sit on an arc around the camera, so each one faces it squarely rather than all of them
	-- sharing one plane and the outer ones turning away.
	local cursor = stage.shift * self._side * (2 * distance * halfTanH) - totalWidth / 2
	local drop = -StageConfig.drop * distance
	local panels: { [string]: CFrame } = {}
	for index, panelId in ipairs(ids) do
		local centre = cursor + widths[index] / 2
		cursor += widths[index] + StageConfig.spacing
		panels[panelId] = camera
			* CFrame.Angles(0, -centre / distance, 0)
			* CFrame.new(0, drop, -distance)
			* CFrame.Angles(0, math.pi, 0)
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

-- Where the camera belongs while the menu is open. Read every frame by the menu camera modifier.
function MenuRigRuntime:getCameraPose(): CFrame?
	local solve = self:_solve()
	return if solve then solve.camera else nil
end

function MenuRigRuntime.get()
	return _instance or MenuRigRuntime.new()
end

return MenuRigRuntime
