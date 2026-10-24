--!strict
-- Menu staging: where the camera stands for each menu view, and how the panels are fitted to it.
-- MenuRigRuntime solves both from the character's position and the yaw it had when the menu opened;
-- see docs/tasks/menu-staging.md.

export type CameraPose = {
	-- Studs from the HumanoidRootPart, in the character's yaw frame. `right` mirrors when the stage
	-- flips sides to clear a wall.
	right: number,
	up: number,
	-- Positive is behind the character, negative ahead of it.
	back: number,
	-- Degrees from the character's facing, turning toward the character. 180 looks straight back.
	turn: number,
}

export type ViewStage = {
	camera: CameraPose,
	-- Share of the view width the panel composition fills.
	fill: number,
	-- Where the composition is centred, as a share of the visible width at the panels' distance.
	-- Positive is right. Used to leave room for the character in views that frame it.
	shift: number,
	-- Side panels whose slot is held open even while hidden, so the primary panel does not move
	-- when one appears.
	reserve: { string },
}

export type SideSlot = {
	side: "left" | "right",
	order: number,
}

local UIMenuConfig = {
	groupName = "menu",
	stage = {
		-- Narrower than gameplay on purpose: at 65 the horizontal FOV on 16:9 is ~97 degrees, and an
		-- off-centre panel is visibly stretched by the wide-angle projection.
		fov = 45,
		-- Height cap, so a tall panel is fitted by height rather than overflowing the frame.
		maxHeightFill = 0.82,
		-- Studs between adjacent panels in a composition.
		spacing = 0.3,
		-- Lowers the composition below the eye line, as a share of its distance.
		drop = 0.03,
		-- Kept between the camera and a wall it is pulled in front of.
		wallClearance = 0.4,
		views = {
			-- Beside the character at a little under shoulder height, the character out of frame:
			-- these views are about reading the panel, and the character only gets in the way.
			system = {
				camera = { right = 3.2, up = 0.7, back = 0, turn = 0 },
				fill = 0.72,
				shift = 0,
				reserve = {},
			} :: ViewStage,
			inventory = {
				camera = { right = 3.2, up = 0.7, back = 0, turn = 0 },
				fill = 0.86,
				shift = 0,
				reserve = { "ItemInspectPanel" },
			} :: ViewStage,
			-- In front of the character and turned back toward it, so the paper doll sits beside the
			-- character it describes.
			equipment = {
				camera = { right = 5.2, up = 0.7, back = -7.4, turn = 122 },
				fill = 0.55,
				shift = 0.2,
				reserve = { "ItemInspectPanel" },
			} :: ViewStage,
		},
	},
	sideSlots = {
		ItemInspectPanel = { side = "right", order = 100 } :: SideSlot,
	},
}

return UIMenuConfig
