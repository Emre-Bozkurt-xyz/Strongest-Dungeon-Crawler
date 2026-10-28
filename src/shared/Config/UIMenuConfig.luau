--!strict
-- Menu staging: where the menu panels sit and where the camera watches them from, per view.
-- MenuRigRuntime solves both from the character's position and the yaw it had when the menu opened;
-- see docs/tasks/menu-staging.md.
--
-- The panel and the camera are placed independently. The panel is where it would make sense for the
-- character to read it; the camera is a seat from which that looks good. Neither aims at the other,
-- so composition is tuned by moving them, not solved by a framing rule.

export type PanelPose = {
	-- Studs from the HumanoidRootPart in the character's yaw frame, to the primary panel's centre.
	ahead: number,
	right: number,
	up: number,
	-- 0 faces the character's head, 1 faces the camera, measured in yaw.
	faceCamera: number,
	-- Degrees, applied after facing. `turn` adds yaw (positive swings the face toward the camera's
	-- side); `tilt` tips the face up, leaning the top away like a tablet held low.
	turn: number,
	tilt: number,
}

export type CameraPose = {
	-- Studs from the HumanoidRootPart in the character's yaw frame. Positive `back` is behind.
	right: number,
	up: number,
	back: number,
	-- Degrees from the character's facing. Positive yaw turns right, negative pitch looks down.
	yaw: number,
	pitch: number,
	-- Vertical field of view, in degrees.
	fov: number,
}

export type ViewStage = {
	panel: PanelPose,
	camera: CameraPose,
}

export type SideSlot = {
	side: "left" | "right",
	order: number,
}

-- Tune these live with the stage tuner (F6 in Studio, src/client/ui/dev/StageTuner.luau), then paste
-- its exported block over `stage`.
local UIMenuConfig = {
	groupName = "menu",
	stage = {
		-- Seconds for the camera to travel to a view's pose, and back to gameplay on close. Fixed
		-- times eased to a hard stop, so the camera arrives rather than drifting in.
		cameraMove = 0.32,
		cameraRelease = 0.22,
		-- World-size multiplier for every menu panel. A 6.5-stud panel at arm's length dwarfs a
		-- 4-stud-wide R6 character; pixelsPerStud scales inversely so the canvas is unchanged.
		panelScale = 0.81,
		-- Studs between adjacent panels.
		spacing = 0.2,
		-- Kept between the camera and a wall it is pulled in front of.
		wallClearance = 0.4,
		-- The view strip rides above whichever panel is primary, centred on it: `gap` studs above its
		-- top edge, and `lift` studs out of its plane toward the reader, so the strip lies over the
		-- panels rather than in them and never fights one for depth while it glides between views.
		viewStrip = { gap = 0.12, lift = 0.08 },
		views = {
			-- Panel squarely in front of the character at chest height, facing it. The camera stands off
			-- the right shoulder and turns back in to look across the character at the panel.
			system = {
				panel = { ahead = 3.5, right = 0.15, up = 1.2, faceCamera = 0.2, turn = -2, tilt = -0.5 },
				camera = { right = 3.2, up = 2.4, back = 2.05, yaw = -24.5, pitch = -9.5, fov = 55 },
			} :: ViewStage,
			inventory = {
				panel = { ahead = 3.5, right = 0.15, up = 1.2, faceCamera = 0.2, turn = -2, tilt = -0.5 },
				camera = { right = 3.2, up = 2.4, back = 2.05, yaw = -24.5, pitch = -9.5, fov = 55 },
			} :: ViewStage,
			-- The paper doll is a tall panel; set back so it and the view strip above it fit between the
			-- top bar and the skill bar, and its lower rows clear the shoulder.
			equipment = {
				panel = { ahead = 4.6, right = 0.15, up = 1.2, faceCamera = 0.2, turn = -2, tilt = -0.5 },
				camera = { right = 3.2, up = 2.4, back = 2.05, yaw = -24.5, pitch = -9.5, fov = 55 },
			} :: ViewStage,
			-- The widest and tallest panel, with a skill's details beside it and the view strip above:
			-- set furthest back, and low, to fit all three.
			loadout = {
				panel = { ahead = 5.2, right = 0.15, up = 1.05, faceCamera = 0.2, turn = -2, tilt = -0.5 },
				camera = { right = 3.2, up = 2.4, back = 2.05, yaw = -24.5, pitch = -9.5, fov = 55 },
			} :: ViewStage,
		},
	},
	sideSlots = {
		ItemInspectPanel = { side = "right", order = 100 } :: SideSlot,
		-- The same place: the two never show together.
		SkillInspectPanel = { side = "right", order = 100 } :: SideSlot,
	},
}

return UIMenuConfig
