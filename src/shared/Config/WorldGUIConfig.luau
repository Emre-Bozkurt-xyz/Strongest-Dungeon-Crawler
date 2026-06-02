--!strict
-- Central world-space GUI tuning values.

local WorldGUIConfig = {
	defaults = {
		baseLerpSpeed = 8.0,
	},
	panels = {
		StatusPreview = {
			offset = Vector3.new(0, 0, 0),
			playerSpaceOffset = Vector3.new(4, 0.7, 0.1),
		},
	},
	cameraPanel = {
		forward = 4.0,
		forwardOverShoulder = 3.5,
		forwardFree = 3.5,
		right = 0.0,
		up = -0.5,
	},
}

return WorldGUIConfig
