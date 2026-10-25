--!strict
-- The default theme: the System as white light on near-black, with cyan for focus
-- (docs/tasks/ui-design-pass.md).

local build = require(script.Parent.ThemeBuilder)

return build("System", "System", {
	-- A trace of blue left in the surfaces, so they read as cool glass rather than flat grey.
	void = Color3.fromRGB(5, 8, 13),
	deep = Color3.fromRGB(16, 21, 30),
	line = Color3.fromRGB(222, 228, 234),
	lineDim = Color3.fromRGB(104, 113, 124),
	focus = Color3.fromRGB(73, 210, 255),
	glow = Color3.fromRGB(168, 240, 255),
	ink = Color3.fromRGB(238, 242, 246),
	inkMuted = Color3.fromRGB(146, 156, 168),
	inkFaint = Color3.fromRGB(86, 94, 106),
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
