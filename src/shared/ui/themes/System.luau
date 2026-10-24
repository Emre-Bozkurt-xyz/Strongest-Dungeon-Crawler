--!strict
-- The default theme: the System as cyan light on near-black navy (docs/tasks/ui-design-pass.md).

local build = require(script.Parent.ThemeBuilder)

return build("System", "System", {
	void = Color3.fromRGB(4, 9, 18),
	deep = Color3.fromRGB(11, 26, 46),
	line = Color3.fromRGB(73, 210, 255),
	lineDim = Color3.fromRGB(31, 110, 150),
	glow = Color3.fromRGB(168, 240, 255),
	ink = Color3.fromRGB(232, 247, 255),
	inkMuted = Color3.fromRGB(126, 166, 189),
	inkFaint = Color3.fromRGB(74, 106, 128),
	alert = Color3.fromRGB(255, 77, 97),
	warn = Color3.fromRGB(255, 192, 77),
	ok = Color3.fromRGB(92, 255, 176),
	rarity = {
		normal = Color3.fromRGB(185, 198, 208),
		magic = Color3.fromRGB(79, 163, 255),
		rare = Color3.fromRGB(255, 210, 90),
		unique = Color3.fromRGB(255, 138, 61),
	},
})
