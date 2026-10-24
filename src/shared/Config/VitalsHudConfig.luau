--!strict
-- The HP/MP/stamina readout over gameplay (docs/tasks/ui-design-pass.md, always-on status).
--
-- It is screen UI that can either follow the character or stay pinned above the skill bar. Following
-- keeps the System's sense of being projected for the player; pinning is the conventional HUD, kept as
-- a mode so it can become a player setting.

local VitalsHudConfig = {
	-- "character" or "pinned".
	anchor = "character",

	-- Screen pixels. The gauges stretch with the width; the height fits two rows and the ring.
	width = 340,
	height = 58,

	-- Following the character. The readout sits beside the HumanoidRootPart, offset along the
	-- camera's right vector so it stays to one side of the character at any orbit angle. The root
	-- does not bob with animations, so following it does not shake.
	character = {
		-- 1 is the character's screen-right, -1 its left.
		side = 1,
		-- Studs from the root, so the gap to the character scales with zoom. Clears the arms at the
		-- closest third-person zoom.
		out = 2.4,
		up = 0.4,
		-- Per second. Fast enough to keep up while running, slow enough that a dash reads as the
		-- readout catching up instead of teleporting.
		followRate = 14,
		-- Screen pixels kept clear at the viewport edges.
		margin = 24,
		-- Closer than this (first person, or zoomed into the head) there is no character on
		-- screen to stand beside, so the readout pins instead.
		minCameraDistance = 2.5,
	},

	pinned = {
		-- Pixels from the bottom of the screen to the readout's bottom edge, clearing the skill bar.
		bottom = 96,
	},

	-- Seconds the readout stays after every vital is back to full.
	lingerSeconds = 2.5,

	lowHealth = {
		-- HP ratio under which the screen edges pulse.
		threshold = 0.3,
		pulseHz = 1.1,
	},
}

return VitalsHudConfig
