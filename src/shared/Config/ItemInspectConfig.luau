--!strict
-- Visual/detail tuning for ItemInspect panel rendering.

local ItemInspectConfig = {
	detailStyles = {
		sectionHeading = {
			sizeScale = 1.0,
			color = Color3.fromRGB(198, 210, 255),
			transparency = 0.08,
		},
		requirementLine = {
			sizeScale = 0.9,
			color = Color3.fromRGB(156, 162, 184),
			transparency = 0.2,
		},
		baseStatLine = {
			sizeScale = 0.95,
			color = Color3.fromRGB(182, 188, 208),
			transparency = 0.12,
		},
		affixLine = {
			sizeScale = 0.95,
			color = Color3.fromRGB(126, 198, 255),
			transparency = 0.03,
		},
	},
	excludedMetaKeys = {
		itemLevel = true,
		rarity = true,
		displayName = true,
	},
}

return ItemInspectConfig
