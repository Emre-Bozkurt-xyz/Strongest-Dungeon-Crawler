--!strict
-- Every world panel, declared in one place.
--
-- React components pull their own state (R16), so what is left per panel is data: which component
-- renders it, where it is placed, and a predicate saying when it should be visible.
--
-- A menu panel's `id` must match `MenuRigRuntime.MENU_PANEL_IDS`, since the stage places panels by
-- id.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MenuTypes = require(script.Parent.Parent.menu.MenuTypes)
local SharedConfig = require(ReplicatedStorage.Shared.Config)

local UIMenuConfig = SharedConfig.UIMenu

export type MenuState = MenuTypes.MenuState

export type SurfaceConfig = {
	-- Panel size in studs. The SurfaceGui's pixel resolution follows from pixelsPerStud.
	width: number,
	height: number,
	thickness: number?,
	pixelsPerStud: number?,
	-- World-size multiplier. The part shrinks or grows and pixelsPerStud scales inversely, so the
	-- canvas resolution -- and every pixel constant a panel derives from it -- is unchanged.
	scale: number?,
	-- Optional. Lay the panel out in this many logical pixels across instead of canvas pixels; see
	-- PanelHost. Set so one logical pixel is about one screen pixel at 1080p staging.
	logicalWidth: number?,
}

-- How WorldGUIManager should place the panel. Passed through to `registerPanel` untouched, so the
-- host has no opinion about where panels live -- menu panels are posed by MenuRigRuntime, and a panel
-- anchored to something in the world supplies its own.
export type Placement = {
	-- Optional: a panel outside the menu rig need not belong to a group.
	group: string?,
	followMode: string?,
	faceCamera: boolean?,
	faceMode: string?,
	faceBlend: number?,
	offset: Vector3?,
	playerSpaceOffset: Vector3?,
	playerOffsetMode: string?,
	maxRadius: number?,
	lerpSpeed: number?,
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
	-- Optional, for `followMode = "target"`: the part to anchor to, re-read whenever visibility is.
	-- A target that moves between things in the world is placement, so it stays out of React (R3).
	followTarget: (() -> BasePart?)?,
	-- Seconds for the show/hide fade.
	fadeDuration: number?,
}

local ItemInspectPanel = require(script.Parent.Parent.panels.ItemInspectPanel)
local SystemPanel = require(script.Parent.Parent.panels.SystemPanel)

-- Studio only: F7 swaps the style tile in for the System panel's content (ui/dev/StyleTile).
if game:GetService("RunService"):IsStudio() then
	SystemPanel = require(script.Parent.Parent.dev.StyleTile).withStyleTile(SystemPanel)
end

local EquipmentPanel = require(script.Parent.Parent.panels.EquipmentPanel)
local InventoryPanel = require(script.Parent.Parent.panels.InventoryPanel)
local WorldLootInspectPanel = require(script.Parent.Parent.panels.WorldLootInspectPanel)

local LootClient = require(script.Parent.Parent.controllers.LootClient)
local LootConfig = SharedConfig.WorldLootInspect

local function isMenuOpen(state: MenuState): boolean
	return state.modal.open
end

-- Placement for a panel that lives on the menu rig. MenuRigRuntime overrides the position by panel
-- id once the menu is open, so these values only matter before the rig takes over.
-- While the menu is open MenuRigRuntime supplies each menu panel's full pose, so registration needs
-- only the group; the follow fields would never be read.
-- See UIMenuConfig.stage.panelScale.
local MENU_PANEL_SCALE = UIMenuConfig.stage.panelScale

local function menuRigPlacement(): Placement
	return { group = UIMenuConfig.groupName }
end

local entries: { PanelEntry } = {
	{
		id = "SystemPanel",
		component = SystemPanel,
		-- Same surface and logical width as the inventory, so the two views read at one size.
		surface = {
			width = 6.478,
			height = 3.549,
			thickness = 0.076,
			pixelsPerStud = 200,
			scale = MENU_PANEL_SCALE,
			logicalWidth = 768,
		},
		placement = menuRigPlacement(),
		isVisible = function(state)
			return isMenuOpen(state) and state.modal.view == "system"
		end,
	},
	{
		id = "InventoryPanel",
		component = InventoryPanel,
		-- 768 logical pixels across is about one screen pixel each at 1080p staging; the 1296px canvas
		-- underneath keeps the text sharp.
		surface = {
			width = 6.478,
			height = 3.549,
			thickness = 0.076,
			pixelsPerStud = 200,
			scale = MENU_PANEL_SCALE,
			logicalWidth = 768,
		},
		placement = menuRigPlacement(),
		isVisible = function(state)
			return isMenuOpen(state) and state.modal.view == "inventory"
		end,
	},
	{
		id = "EquipmentPanel",
		component = EquipmentPanel,
		-- Studs from the Studio-authored part. 200 px/stud gives a 1052x1241 canvas, which also
		-- reproduces the original candidate grid's 150px cells and 30px gaps almost exactly.
		surface = { width = 5.259, height = 6.207, thickness = 0.076, pixelsPerStud = 200, scale = MENU_PANEL_SCALE },
		placement = menuRigPlacement(),
		isVisible = function(state)
			return isMenuOpen(state) and state.modal.view == "equipment"
		end,
	},
	{
		id = "ItemInspectPanel",
		component = ItemInspectPanel,
		-- 340 logical pixels across is about one screen pixel each at 1080p staging; the 562px canvas
		-- underneath keeps the text sharp.
		surface = {
			width = 1.875,
			height = 3.34,
			thickness = 0.076,
			pixelsPerStud = 300,
			scale = MENU_PANEL_SCALE,
			logicalWidth = 340,
		},
		placement = menuRigPlacement(),
		-- Hidden over the system view, which has no item context to inspect against.
		isVisible = function(state)
			return state.inspect ~= nil and isMenuOpen(state) and state.modal.view ~= "system"
		end,
	},
	{
		id = "WorldLootInspectPanel",
		component = WorldLootInspectPanel,
		-- Studs and density from the Studio-authored part: an 822x1150 canvas. LootList derives its
		-- row height from these, so change both together.
		surface = { width = 2.056, height = 2.874, thickness = 0.076, pixelsPerStud = 400 },
		-- Anchored above the nearest drop, facing the camera rather than the player, so it reads
		-- from wherever the player approaches it.
		placement = {
			group = LootConfig.groupName,
			faceCamera = true,
			faceMode = "camera",
			followMode = "target",
			offset = LootConfig.panel.offset,
			maxRadius = LootConfig.panel.maxRadius,
			lerpSpeed = LootConfig.panel.lerpSpeed,
		},
		followTarget = function()
			local lead = LootClient.getSnapshot().entries[1]
			return if lead then lead.part else nil
		end,
		-- Driven by loot in range, not by menu state. LootClient already empties the list while a
		-- menu is open, so the menu rule needs no restating here.
		isVisible = function(_state)
			return #LootClient.getSnapshot().entries > 0
		end,
		watch = function(notify)
			return LootClient.onChanged(notify)
		end,
		fadeDuration = 0.15,
	},
}

local PanelRegistry = {}

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
