--!strict
-- Central camera tuning values shared across client runtime modules.

local CameraConfig = {
	baseline = {
		shoulderRight = 2.0,
		shoulderUp = 2.75,
		shoulderBack = 6.0,
		followSmoothness = 0.5,
		lookSmoothness = 0.15,
		minCameraDistance = 1.0,
		defaultMinZoom = 2.5,
		defaultMaxZoom = 16.0,
		baseFov = 70,
		mouseSensYaw = 0.0025,
		mouseSensPitch = 0.0020,
		pitchMin = math.rad(-45),
		pitchMax = math.rad(35),
		lookForwardDistance = 25.0,
		lookUpOffsetY = 1.5,
		focus = {
			distance = 6.0,
			up = 0.5,
			tween = 0.3,
		},
	},
	modifiers = {
		-- The pose and FOV come from the menu stage (UIMenuConfig.stage); this only sets how the
		-- camera travels there. Per-frame lerp factors, so lower is a longer, softer move.
		systemMenuFocus = {
			priority = 50,
			followSmoothness = 0.16,
			lookSmoothness = 0.16,
			lockYaw = true,
			lockPitch = true,
		},
	},
}

return CameraConfig
