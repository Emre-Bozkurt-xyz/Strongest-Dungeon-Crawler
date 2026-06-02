--!strict
-- Central tuning values for diegetic menu panel placement and layout.

export type PanelPlacement = {
	offset: Vector3,
	playerSpaceOffset: Vector3,
	faceBlend: number,
	playerOffsetMode: "full" | "yaw",
	maxRadius: number,
}

local UIMenuConfig = {
	groupName = "menu",
	anchor = {
		followSpeed = 22,
		snapDistance = 10,
	},
	groupParams = {
		lerpSpeed = 14,
		minRadius = 2.7,
		maxRadius = 8.0,
	},
	layout = {
		spacing = 0.4,
		includeHidden = false,
		space = "player",
		surface = "arc",
		arcRadius = 8.5,
		arcDepthScale = 0.28,
		arcDepthSign = -1,
		panelSlots = {
			SystemPanel = {
				role = "primary",
				side = "center",
				order = 0,
			},
			InventoryPanel = {
				role = "primary",
				side = "center",
				order = 0,
			},
			EquipmentPanel = {
				role = "primary",
				side = "center",
				order = 0,
			},
			ItemInspectPanel = {
				role = "side",
				side = "right",
				order = 100,
			},
		},
	},
	panels = {
		SystemPanel = {
			offset = Vector3.new(0, 0.2, 0),
			playerSpaceOffset = Vector3.new(0.300, 1.000, 2.100),
			faceBlend = 0.35,
			playerOffsetMode = "yaw",
			maxRadius = 16.0,
		} :: PanelPlacement,
		InventoryPanel = {
			offset = Vector3.new(0, 0.2, 0),
			playerSpaceOffset = Vector3.new(0.3, 1.0, 3.8),
			faceBlend = 0.35,
			playerOffsetMode = "yaw",
			maxRadius = 16.0,
		} :: PanelPlacement,
		EquipmentPanel = {
			offset = Vector3.new(0, 0.2, 0),
			playerSpaceOffset = Vector3.new(0.3, 1.0, 3.8),
			faceBlend = 0.35,
			playerOffsetMode = "yaw",
			maxRadius = 16.0,
		} :: PanelPlacement,
		ItemInspectPanel = {
			offset = Vector3.new(0, 0.2, 0),
			playerSpaceOffset = Vector3.new(0.3, 1.0, 3.8),
			faceBlend = 0.35,
			playerOffsetMode = "yaw",
			maxRadius = 16.0,
		} :: PanelPlacement,
	},
	centerWeights = {
		systemPanelBootstrap = {
			SystemPanel = 2.25,
			_default = 1.0,
		},
		systemView = {
			SystemPanel = 2.5,
			_default = 0.75,
		},
		inspectOnly = {
			ItemInspectPanel = 2.4,
			_default = 1.0,
		},
		inventoryView = {
			InventoryPanel = 2.8,
			ItemInspectPanel = 0.85,
			_default = 0.6,
		},
		equipmentView = {
			EquipmentPanel = 2.8,
			ItemInspectPanel = 0.85,
			_default = 0.6,
		},
	},
	systemPanel = {
		radiusPaddingFloor = 0.5,
	},
}

return UIMenuConfig
