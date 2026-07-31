--!strict
-- Every world panel, declared in one place.
--
-- Replaces the eight PanelPlugin modules (R16). A plugin existed to push state into an imperative
-- runtime; React components pull, so what is left per panel is data: which component renders it,
-- and a predicate over menu state saying when it should be visible.
--
-- `id` must match the ids `MenuRigRuntime.MENU_PANEL_IDS` and `SharedConfig.UIMenu.panels` already
-- use, since placement is looked up by id.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PanelPluginTypes = require(script.Parent.Parent.menu.PanelPluginTypes)
local SharedConfig = require(ReplicatedStorage.Shared.Config)

local UIMenuConfig = SharedConfig.UIMenu
local WorldGUIConfig = SharedConfig.WorldGUI

export type MenuState = PanelPluginTypes.MenuState

export type SurfaceConfig = {
	-- Panel size in studs. The SurfaceGui's pixel resolution follows from pixelsPerStud.
	width: number,
	height: number,
	thickness: number?,
	pixelsPerStud: number?,
}

-- How WorldGUIManager should place the panel. Passed through to `registerPanel` untouched, so the
-- host has no opinion about where panels live -- menu panels read this from UIMenuConfig, the status
-- preview from WorldGUIConfig, and a panel anchored to something in the world can supply its own.
export type Placement = {
	-- Optional: a panel outside the menu rig belongs to no group (the status preview does not).
	group: string?,
	followMode: string?,
	faceCamera: boolean?,
	faceMode: string?,
	faceBlend: number?,
	offset: Vector3?,
	playerSpaceOffset: Vector3?,
	playerOffsetMode: string?,
	maxRadius: number?,
}

export type PanelEntry = {
	id: string,
	component: any,
	surface: SurfaceConfig,
	placement: Placement,
	-- Pure predicate. Each plugin's bespoke shouldShow* collapses to one of these.
	--
	-- Menu state is passed because most panels only depend on it. A panel whose visibility depends
	-- on something else (nearby loot, a controller's state) reads that source directly here and pairs
	-- it with `watch` so the runtime knows when to re-evaluate.
	isVisible: (state: MenuState) -> boolean,
	-- Optional. Called with a callback that re-evaluates visibility; returns an unsubscribe. Panels
	-- driven purely by menu state do not need it -- the runtime already re-evaluates on every change.
	watch: ((notify: () -> ()) -> () -> ())?,
	-- Seconds for the show/hide fade.
	fadeDuration: number?,
}

local ItemInspectPanel = require(script.Parent.Parent.panels.ItemInspectPanel)
local SystemPanel = require(script.Parent.Parent.panels.SystemPanel)
local StatusPreviewPanel = require(script.Parent.Parent.panels.StatusPreviewPanel)
local EquipmentPanel = require(script.Parent.Parent.panels.EquipmentPanel)
local InventoryPanel = require(script.Parent.Parent.panels.InventoryPanel)

local function isMenuOpen(state: MenuState): boolean
	return state.modal.open
end

-- Placement for a panel that lives on the menu rig. MenuRigRuntime overrides the position by panel
-- id once the menu is open, so these values only matter before the rig takes over.
local function menuRigPlacement(id: string): Placement
	local configured = (UIMenuConfig.panels :: any)[id]
	return {
		group = UIMenuConfig.groupName,
		faceCamera = true,
		faceMode = "playerYaw",
		faceBlend = configured and configured.faceBlend or 0.35,
		followMode = "player",
		offset = configured and configured.offset or Vector3.new(),
		playerSpaceOffset = configured and configured.playerSpaceOffset or Vector3.new(),
		playerOffsetMode = configured and configured.playerOffsetMode or "yaw",
		maxRadius = configured and configured.maxRadius,
	}
end

local entries: { PanelEntry } = {
	{
		id = "SystemPanel",
		component = SystemPanel,
		-- Studs from the Studio-authored part. 200 px/stud gives a 1296x710 canvas.
		surface = { width = 6.478, height = 3.549, thickness = 0.076, pixelsPerStud = 200 },
		placement = menuRigPlacement("SystemPanel"),
		isVisible = function(state)
			return isMenuOpen(state) and state.modal.view == "system"
		end,
	},
	{
		id = "InventoryPanel",
		component = InventoryPanel,
		-- Studs from the Studio-authored part; same width as SystemPanel, so the same px/stud.
		surface = { width = 6.478, height = 3.549, thickness = 0.076, pixelsPerStud = 200 },
		placement = menuRigPlacement("InventoryPanel"),
		isVisible = function(state)
			return isMenuOpen(state) and state.modal.view == "inventory"
		end,
	},
	{
		id = "EquipmentPanel",
		component = EquipmentPanel,
		-- Studs from the Studio-authored part. 200 px/stud gives a 1052x1241 canvas, which also
		-- reproduces the original candidate grid's 150px cells and 30px gaps almost exactly.
		surface = { width = 5.259, height = 6.207, thickness = 0.076, pixelsPerStud = 200 },
		placement = menuRigPlacement("EquipmentPanel"),
		isVisible = function(state)
			return isMenuOpen(state) and state.modal.view == "equipment"
		end,
	},
	{
		-- "StatusPreview", not "StatusPreviewPanel": this is the WorldGUIManager panel name the old
		-- controller registered under, and WorldGUIConfig and the DevTuning paths are keyed on it.
		id = "StatusPreview",
		component = StatusPreviewPanel,
		-- Studs from the Studio-authored part. 300 px/stud gives an 897x396 canvas.
		surface = { width = 2.991, height = 1.321, thickness = 0.076, pixelsPerStud = 300 },
		-- Character-anchored, not on the menu rig, so it states its own placement. Only the fields
		-- the old controller set -- PanelHost fills in no defaults.
		placement = {
			faceCamera = true,
			followMode = "player",
			offset = WorldGUIConfig.panels.StatusPreview.offset,
			playerSpaceOffset = WorldGUIConfig.panels.StatusPreview.playerSpaceOffset,
		},
		-- The inverse of every menu panel: this is the ambient gameplay readout, so it yields
		-- whenever a modal is up.
		isVisible = function(state)
			return not state.modal.open
		end,
	},
	{
		id = "ItemInspectPanel",
		component = ItemInspectPanel,
		-- Studs from the Studio-authored part. 300 px/stud gives a 562x1002 canvas, enough for the
		-- info rows to stay legible at this physical size.
		surface = { width = 1.875, height = 3.34, thickness = 0.076, pixelsPerStud = 300 },
		placement = menuRigPlacement("ItemInspectPanel"),
		-- Matches the old ItemInspectPanelPlugin.shouldShowInspect exactly.
		isVisible = function(state)
			return state.inspect ~= nil and isMenuOpen(state) and state.modal.view ~= "system"
		end,
	},
}

local PanelRegistry = {}

-- Exposed so a panel declared elsewhere can adopt menu-rig placement without restating it.
PanelRegistry.menuRigPlacement = menuRigPlacement

function PanelRegistry.list(): { PanelEntry }
	return entries
end

function PanelRegistry.get(id: string): PanelEntry?
	for _, entry in ipairs(entries) do
		if entry.id == id then
			return entry
		end
	end
	return nil
end

return PanelRegistry
