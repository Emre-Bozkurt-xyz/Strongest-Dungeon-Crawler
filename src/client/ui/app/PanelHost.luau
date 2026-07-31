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
-- touches, and fading tweens its GroupTransparency -- one property, one owner.

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local WorldGUIManager = require(script.Parent.Parent.Parent.WorldGUIManager)
local mountPanel = require(script.Parent.mountPanel)
local PanelRegistry = require(script.Parent.PanelRegistry)

local PanelHost = {}
PanelHost.__index = PanelHost

export type PanelHostType = {
	setVisible: (self: PanelHostType, visible: boolean) -> (),
	render: (self: PanelHostType, element: any) -> (),
	destroy: (self: PanelHostType) -> (),
}

local DEFAULT_FADE = 0.2

local function buildPart(entry: PanelRegistry.PanelEntry): BasePart
	local part = Instance.new("Part")
	part.Name = entry.id
	part.Size = Vector3.new(entry.surface.width, entry.surface.height, entry.surface.thickness or 0.1)
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

local function buildSurface(entry: PanelRegistry.PanelEntry, part: BasePart): (SurfaceGui, CanvasGroup)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Surface"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = entry.surface.pixelsPerStud or 100
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.Adornee = part
	-- Disabled alongside CanQuery so a hidden panel neither renders nor absorbs pointer input.
	gui.Enabled = false
	gui.Parent = part

	-- The fade target. React mounts inside it and never sets GroupTransparency.
	local group = Instance.new("CanvasGroup")
	group.Name = "Content"
	group.Size = UDim2.fromScale(1, 1)
	group.BackgroundTransparency = 1
	group.BorderSizePixel = 0
	group.GroupTransparency = 1
	group.Parent = gui

	return gui, group
end

function PanelHost.new(entry: PanelRegistry.PanelEntry): PanelHostType
	local self = setmetatable({}, PanelHost) :: any

	self._entry = entry
	self._visible = false
	self._destroyed = false
	self._tween = nil :: Tween?

	local part = buildPart(entry)
	local gui, group = buildSurface(entry, part)
	self._part = part
	self._gui = gui
	self._group = group

	-- Parented up front so placement and the initial fade have somewhere to run. It is invisible
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
	})

	-- The part and the WGM registration exist by now, so a failed mount has to undo them. Leaving
	-- them behind would let the next attempt register a second part under the same panel id.
	local ok, mountedOrErr = pcall(mountPanel, group, nil)
	if not ok then
		wgm:unregisterPanel(entry.id)
		part:Destroy()
		error(mountedOrErr)
	end
	self._mounted = mountedOrErr

	return self :: any
end

function PanelHost.render(self: any, element: any)
	if self._destroyed then
		return
	end
	self._mounted.render(element)
end

function PanelHost.setVisible(self: any, visible: boolean)
	if self._destroyed or self._visible == visible then
		return
	end
	self._visible = visible

	local running = self._tween
	if running then
		running:Cancel()
		self._tween = nil
	end

	-- Input is gated on the way in before the fade starts, and on the way out immediately, so a
	-- panel is never clickable while it is invisible or on its way to being so.
	self._part.CanQuery = visible
	if visible then
		self._gui.Enabled = true
	end

	local duration = self._entry.fadeDuration or DEFAULT_FADE
	local tween = TweenService:Create(
		self._group,
		TweenInfo.new(duration, Enum.EasingStyle.Quart),
		{ GroupTransparency = if visible then 0 else 1 }
	)
	self._tween = tween

	if not visible then
		-- Deferred to the end of the fade so the panel stays rendered while it fades, and guarded
		-- because setVisible(true) may land mid-fade -- Cancel does not stop Completed from firing.
		tween.Completed:Connect(function(state: Enum.PlaybackState)
			if state == Enum.PlaybackState.Completed and not self._visible and not self._destroyed then
				self._gui.Enabled = false
			end
		end)
	end

	tween:Play()
end

function PanelHost.destroy(self: any)
	if self._destroyed then
		return
	end
	self._destroyed = true

	local running = self._tween
	if running then
		running:Cancel()
		self._tween = nil
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
