--!strict
-- The System in violet: the same projected-light language as the default, in the purple the game's
-- first UI used. The first alternate skin, and proof that a palette alone is enough to make one.

local build = require(script.Parent.ThemeBuilder)

return build("SystemViolet", "System Violet", {
	void = Color3.fromRGB(10, 4, 22),
	deep = Color3.fromRGB(30, 14, 56),
	line = Color3.fromRGB(176, 128, 255),
	lineDim = Color3.fromRGB(92, 58, 150),
	glow = Color3.fromRGB(222, 200, 255),
	ink = Color3.fromRGB(243, 236, 255),
	inkMuted = Color3.fromRGB(164, 146, 196),
	inkFaint = Color3.fromRGB(104, 88, 136),
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
