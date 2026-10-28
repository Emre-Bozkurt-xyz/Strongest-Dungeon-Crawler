--!strict
-- Uploaded artwork for the mastery mind-space (docs/planning/mastery-mind-space.md): mastery
-- emblems, node icons and embroidery frames, keyed by the file name they were generated under
-- (`mastery.<Track>`, `frame.<kind>`, or a node id).
--
-- Every image is white on transparent so the UI can tint it. A key with no art yet returns nil and
-- the UI falls back to a plain look, so art never blocks the UI.
--
-- Generated art sits on its canvas with uneven margins (a tall sword, a wide bow), so each image is
-- cropped to the bounds of what is drawn (measured from the uploaded image's alpha). That way
-- `ScaleType.Fit` gives every emblem the same visual size.

local MasteryArt = {}

export type Art = {
	image: string,
	-- The drawn part of the image, in its pixels.
	offset: Vector2,
	size: Vector2,
}

-- key -> { asset id, crop x, crop y, crop width, crop height }
local IMAGES: { [string]: { number } } = {
	["frame.select"] = { 84637826682743, 216, 196, 606, 646 },
	["frame.form"] = { 132870562779474, 174, 158, 662, 726 },
	["frame.attuned_node"] = { 115940567650886, 228, 194, 618, 632 },
	["frame.attuned_mastery"] = { 140100993308778, 148, 256, 760, 518 },

	["mastery.Blade"] = { 123021386461532, 380, 54, 266, 930 },
	["mastery.Blunt"] = { 138478663685364, 198, 16, 630, 994 },
	["mastery.Magic"] = { 100348819495850, 322, 98, 450, 846 },
	["mastery.Ranged"] = { 101540418212709, 180, 122, 718, 762 },
	["mastery.Fire"] = { 107421717638137, 336, 124, 344, 778 },
	["mastery.Frost"] = { 85185573844385, 194, 130, 646, 768 },

	["magic.mana_ball"] = { 86699757079661, 274, 118, 506, 788 },
	["magic.mana_bolt"] = { 92285175240327, 206, 174, 688, 718 },
	["magic.piercing_bolt"] = { 78244371495910, 174, 130, 776, 764 },
	["magic.mana_burst"] = { 87638028616338, 94, 116, 846, 796 },
	["magic.scatter"] = { 131484555279338, 48, 84, 952, 864 },
	["magic.mana_comet"] = { 77587481830775, 54, 18, 964, 994 },
	["blade.strike"] = { 88362708294672, 124, 40, 880, 958 },
	["blade.cleave"] = { 102696903405113, 100, 102, 828, 826 },
	["blade.flurry"] = { 127818723711009, 74, 88, 878, 848 },
	["blade.twin_fangs"] = { 83920157900598, 58, 48, 912, 948 },
	["blade.dancing_steel"] = { 139691065152737, 166, 116, 726, 784 },
	["blunt.punches"] = { 122875330447586, 168, 310, 752, 482 },
}

-- The four corner pieces of `frame.attuned_mastery` (top left, top right, bottom left, bottom
-- right), drawn separately so they sit on a box's corners at any box size.
local CORNERS: { { number } } = {
	{ 148, 256, 190, 186 },
	{ 726, 256, 180, 186 },
	{ 148, 590, 192, 184 },
	{ 726, 592, 182, 182 },
}

local function art(id: number, rect: { number }, from: number): Art
	return {
		image = `rbxassetid://{id}`,
		offset = Vector2.new(rect[from], rect[from + 1]),
		size = Vector2.new(rect[from + 2], rect[from + 3]),
	}
end

function MasteryArt.get(key: string): Art?
	local entry = IMAGES[key]
	return if entry then art(entry[1], entry, 2) else nil
end

function MasteryArt.corners(): { Art }?
	local entry = IMAGES["frame.attuned_mastery"]
	if not entry then
		return nil
	end
	local out: { Art } = {}
	for _, rect in ipairs(CORNERS) do
		table.insert(out, art(entry[1], rect, 1))
	end
	return out
end

-- ImageLabel props showing `art`, cropped to what is drawn.
function MasteryArt.imageProps(value: Art): { [string]: any }
	return {
		Image = value.image,
		ImageRectOffset = value.offset,
		ImageRectSize = value.size,
	}
end

return MasteryArt
