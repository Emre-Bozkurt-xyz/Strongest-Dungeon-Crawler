--!strict
-- Owns one world panel's surface: creates the part and SurfaceGui, registers it with
-- WorldGUIManager for placement, mounts a React root on it, and owns its visibility.
--
-- This is the role the old panel runtimes held. WorldGUIManager and MenuRigRuntime are unchanged --
-- the rig positions by panel id and never touches instances, so a code-created part registers
-- exactly like a Studio-authored one (R16).
--
-- Visibility is deliberately NOT delegated to WorldGUIManager:setPanelVisibility. That fades by
-- tweening BackgroundTransparency/TextTransparency on every GuiObject descendant and caching the
-- originals as attributes. React owns those properties and rewrites them on re-render, so the tween
-- and the reconciler would fight, and the cached "original" would be whatever value happened to be
-- live at the first hide. Instead the React tree is mounted inside a CanvasGroup that React never
-- touches, and the host's own transition drives it -- a few properties, one owner.
--
-- A panel switches on rather than fading in (shared/ui/SwitchOn, timed by theme.transitions): this
-- host draws those frames onto a clip band and two light lines.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Ease = require(ReplicatedStorage.Shared.ui.Ease)
local SwitchOn = require(ReplicatedStorage.Shared.ui.SwitchOn)
local Themes = require(ReplicatedStorage.Shared.ui.themes)
local WorldGUIManager = require(script.Parent.Parent.Parent.WorldGUIManager)
local mountPanel = require(script.Parent.mountPanel)
local PanelRegistry = require(script.Parent.PanelRegistry)

local PanelHost = {}
PanelHost.__index = PanelHost

export type PanelHostType = {
	setVisible: (self: PanelHostType, visible: boolean, delay: number?) -> (),
	isVisible: (self: PanelHostType) -> boolean,
	setFollowTarget: (self: PanelHostType, target: BasePart?) -> (),
	setScale: (self: PanelHostType, scale: number) -> (),
	present: (self: PanelHostType, element: any, visible: boolean, delay: number?) -> (),
	destroy: (self: PanelHostType) -> (),
}

-- Canvas pixels: the light lines at the band's edges.
local LINE_THICKNESS = 3
-- The band never quite reaches zero height while shown, so the lines have a gap to sit either side of.
local MIN_BAND = 0.004

type Surface = {
	gui: SurfaceGui,
	group: CanvasGroup,
	clip: Frame,
	lines: { Frame },
	mountRoot: GuiObject,
}

local function buildPart(entry: PanelRegistry.PanelEntry): BasePart
	local part = Instance.new("Part")
	part.Name = entry.id
	local scale = entry.surface.scale or 1
	part.Size = Vector3.new(entry.surface.width * scale, entry.surface.height * scale, entry.surface.thickness or 0.1)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	-- Queryable only while visible. World-space SurfaceGui pointer input needs the part to be
	-- hit-testable, but GroupTransparency does not disable hit-testing the way Visible=false does,
	-- so a faded-out panel left queryable is an invisible click-blocker over whatever it parks on.
	part.CanQuery = false
	part.Transparency = 1
	part.CastShadow = false
	return part
end

local function buildSurface(entry: PanelRegistry.PanelEntry, part: BasePart): Surface
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Surface"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = (entry.surface.pixelsPerStud or 100) / (entry.surface.scale or 1)
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.Adornee = part
	-- Disabled alongside CanQuery so a hidden panel neither renders nor absorbs pointer input.
	gui.Enabled = false
	gui.Parent = part

	-- Opacity for the whole panel. React mounts below it and never sets GroupTransparency.
	local group = Instance.new("CanvasGroup")
	group.Name = "Content"
	group.Size = UDim2.fromScale(1, 1)
	group.BackgroundTransparency = 1
	group.BorderSizePixel = 0
	group.GroupTransparency = 1
	group.Parent = gui

	-- The band: a clip that grows from the centre line. The canvas inside keeps the full surface size
	-- in pixels and stays centred, so the panel is revealed in place rather than squashed.
	local canvasWidth = entry.surface.width * (entry.surface.pixelsPerStud or 100)
	local canvasHeight = entry.surface.height * (entry.surface.pixelsPerStud or 100)
	local clip = Instance.new("Frame")
	clip.Name = "Band"
	clip.AnchorPoint = Vector2.new(0.5, 0.5)
	clip.Position = UDim2.fromScale(0.5, 0.5)
	clip.Size = UDim2.fromScale(1, MIN_BAND)
	clip.BackgroundTransparency = 1
	clip.BorderSizePixel = 0
	clip.ClipsDescendants = true
	clip.Parent = group

	local canvas = Instance.new("Frame")
	canvas.Name = "Canvas"
	canvas.AnchorPoint = Vector2.new(0.5, 0.5)
	canvas.Position = UDim2.fromScale(0.5, 0.5)
	canvas.Size = UDim2.fromOffset(canvasWidth, canvasHeight)
	canvas.BackgroundTransparency = 1
	canvas.BorderSizePixel = 0
	canvas.Parent = clip

	local accent = Themes.getDefault().color.accent
	local lines = {}
	for index = 1, 2 do
		local line = Instance.new("Frame")
		line.Name = `ScanLine{index}`
		line.AnchorPoint = Vector2.new(0.5, 0.5)
		line.Position = UDim2.fromScale(0.5, 0.5)
		line.Size = UDim2.new(1, 0, 0, LINE_THICKNESS)
		line.BackgroundColor3 = accent
		line.BackgroundTransparency = 1
		line.BorderSizePixel = 0
		line.ZIndex = 10
		-- Outside the CanvasGroup: the group is still transparent while the line draws out.
		line.Parent = gui
		table.insert(lines, line)
	end

	local surface: Surface = { gui = gui, group = group, clip = clip, lines = lines, mountRoot = canvas }

	-- A surface declaring a logical width is authored in that many pixels across, scaled up to fill
	-- the real canvas. The canvas keeps its resolution, so text stays sharp, while the panel lays out in
	-- units close to screen pixels at staging and the theme's type scale means what it says.
	local logicalWidth = entry.surface.logicalWidth
	if not logicalWidth then
		return surface
	end
	local factor = canvasWidth / logicalWidth
	local logical = Instance.new("Frame")
	logical.Name = "Logical"
	logical.Size = UDim2.fromScale(1 / factor, 1 / factor)
	logical.BackgroundTransparency = 1
	logical.BorderSizePixel = 0
	logical.Parent = canvas
	local uiScale = Instance.new("UIScale")
	uiScale.Scale = factor
	uiScale.Parent = logical
	-- React clears its container's children on first render, which would take the UIScale with them,
	-- so React mounts one level down.
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Parent = logical
	surface.mountRoot = root

	return surface
end

function PanelHost.new(entry: PanelRegistry.PanelEntry): PanelHostType
	local self = setmetatable({}, PanelHost) :: any

	self._entry = entry
	self._visible = false
	self._destroyed = false
	self._transition = nil :: RBXScriptConnection?
	-- Band height, 0..1, kept between transitions so a reversal starts from where the last one was.
	self._band = 0
	self._hasContent = false
	self._followTarget = nil :: BasePart?

	local part = buildPart(entry)
	local surface = buildSurface(entry, part)
	local mountRoot = surface.mountRoot
	self._part = part
	self._gui = surface.gui
	self._group = surface.group
	self._clip = surface.clip
	self._lines = surface.lines

	-- Parented up front so placement and the first transition have somewhere to run. It is invisible
	-- until setVisible, since GroupTransparency starts at 1.
	part.Parent = Workspace

	-- Placement comes from the entry rather than being looked up here, so this host works for a
	-- menu-rig panel, a character-anchored one, and anything anchored to a thing in the world.
	local placement = entry.placement
	local wgm = WorldGUIManager.getInstance()
	-- Passed through as authored, with no defaults filled in here. Substituting a faceMode or
	-- playerOffsetMode the caller did not ask for silently changes how a panel tracks the player;
	-- menu panels get their values from `menuRigPlacement`, and anything else states its own.
	wgm:registerPanel({
		name = entry.id,
		part = part,
		group = placement.group,
		faceCamera = placement.faceCamera,
		faceMode = placement.faceMode,
		faceBlend = placement.faceBlend,
		followMode = placement.followMode,
		offset = placement.offset,
		playerSpaceOffset = placement.playerSpaceOffset,
		playerOffsetMode = placement.playerOffsetMode,
		maxRadius = placement.maxRadius,
		lerpSpeed = placement.lerpSpeed,
	})

	-- The part and the WGM registration exist by now, so a failed mount has to undo them. Leaving
	-- them behind would let the next attempt register a second part under the same panel id.
	local ok, mountedOrErr = pcall(mountPanel, mountRoot, nil)
	if not ok then
		wgm:unregisterPanel(entry.id)
		part:Destroy()
		error(mountedOrErr)
	end
	self._mounted = mountedOrErr

	return self :: any
end

-- Shows or hides the panel with `element` as its content. A panel on its way out keeps rendering
-- until it has closed -- the element it is handed carries `visible = false`, so the content can hold
-- its last state -- and only then is the subtree dropped; dropping it at the start would close an
-- empty surface. `delay` holds an opening back, for a view switch.
function PanelHost.present(self: any, element: any, visible: boolean, delay: number?)
	if self._destroyed then
		return
	end
	if visible or self._hasContent then
		self._mounted.render(element)
		self._hasContent = true
	end
	self:setVisible(visible, delay)
end

function PanelHost.isVisible(self: any): boolean
	return self._visible
end

function PanelHost._draw(self: any, frame: SwitchOn.Frame)
	local height = math.max(frame.band, MIN_BAND)
	self._band = frame.band
	self._clip.Size = UDim2.fromScale(1, height)
	self._group.GroupTransparency = frame.transparency
	for index, line in ipairs(self._lines) do
		local edge = if index == 1 then -0.5 else 0.5
		line.Position = UDim2.fromScale(0.5, 0.5 + edge * height)
		line.Size = UDim2.new(frame.lineLength, 0, 0, LINE_THICKNESS)
		line.BackgroundTransparency = frame.lineTransparency
	end
end

function PanelHost.setVisible(self: any, visible: boolean, delay: number?)
	if self._destroyed or self._visible == visible then
		return
	end
	self._visible = visible

	local running = self._transition
	if running then
		running:Disconnect()
		self._transition = nil
	end

	-- Input is gated on the way in before the transition starts, and on the way out immediately, so a
	-- panel is never clickable while it is invisible or on its way to being so.
	self._part.CanQuery = visible
	if visible then
		self._gui.Enabled = true
		-- A hidden panel's last position is stale -- wherever it was parked, possibly across the
		-- map -- so it appears where it belongs rather than flying in from there.
		WorldGUIManager.getInstance():snapPanel(self._entry.id)
	end

	local timing = Themes.getDefault().transitions
	local from = self._band
	local duration = SwitchOn.duration(visible, from, timing)
	local hold = if visible then delay or 0 else 0
	local started = os.clock()

	local function finish()
		if self._transition then
			self._transition:Disconnect()
			self._transition = nil
		end
		if not visible and not self._destroyed then
			self._gui.Enabled = false
			self._mounted.render(nil)
			self._hasContent = false
		end
	end

	local function step()
		local elapsed = os.clock() - started - hold
		if elapsed < 0 then
			return
		end
		local t = if duration > 0 then Ease.clamp01(elapsed / duration) else 1
		self:_draw(if t >= 1 and visible then SwitchOn.OPEN else SwitchOn.frame(visible, t, from))
		if t >= 1 then
			finish()
		end
	end

	-- Closed until its delayed start, rather than showing the whole panel for the wait.
	if visible and from == 0 then
		self:_draw(SwitchOn.CLOSED)
	end
	self._transition = RunService.Heartbeat:Connect(step)
	step()
end

-- For a panel whose anchor changes at runtime, e.g. the nearest loot drop. nil clears it, which
-- leaves the panel where it is: WorldGUIManager holds position when a target panel has no target.
function PanelHost.setFollowTarget(self: any, target: BasePart?)
	if self._destroyed or self._followTarget == target then
		return
	end
	local appearing = self._followTarget == nil
	self._followTarget = target

	local wgm = WorldGUIManager.getInstance()
	wgm:setPanelFollowTarget(self._entry.id, target)

	-- Snap rather than lerp when a target appears from nothing. The panel's last position belongs to
	-- whatever it followed before, possibly across the map, and it would fly in from there. Moving
	-- between two live targets still lerps.
	if target and appearing then
		wgm:snapPanel(self._entry.id)
	end
end

-- Resizes the panel in the world without touching its canvas: pixelsPerStud moves inversely, so every
-- pixel a component lays out stays where it was.
function PanelHost.setScale(self: any, scale: number)
	if self._destroyed then
		return
	end
	local surface = self._entry.surface
	self._part.Size = Vector3.new(surface.width * scale, surface.height * scale, self._part.Size.Z)
	self._gui.PixelsPerStud = (surface.pixelsPerStud or 100) / scale
end

function PanelHost.destroy(self: any)
	if self._destroyed then
		return
	end
	self._destroyed = true

	local running = self._transition
	if running then
		running:Disconnect()
		self._transition = nil
	end

	-- Unmount before destroying: React must drop its host instances while they still exist.
	self._mounted.unmount()

	local wgm = WorldGUIManager.peekInstance()
	if wgm then
		wgm:unregisterPanel(self._entry.id)
	end

	self._part:Destroy()
end

return PanelHost
