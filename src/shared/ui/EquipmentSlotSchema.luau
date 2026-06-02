--!strict
-- Canonical equipment slot ids and normalization helpers for UI/runtime binding.

export type EquipmentSlotId =
	"Main"
	| "Secondary"
	| "Head"
	| "Neck"
	| "Body"
	| "Hands"
	| "Waist"
	| "Feet"
	| "Ring1"
	| "Ring2"

local SLOT_IDS: { EquipmentSlotId } = {
	"Main",
	"Secondary",
	"Head",
	"Neck",
	"Body",
	"Hands",
	"Waist",
	"Feet",
	"Ring1",
	"Ring2",
}

local ALIASES: { [string]: EquipmentSlotId } = {
	main = "Main",
	primary = "Main",
	weapon = "Main",

	secondary = "Secondary",
	offhand = "Secondary",

	head = "Head",
	helmet = "Head",

	neck = "Neck",
	amulet = "Neck",

	body = "Body",
	chest = "Body",
	torso = "Body",

	hands = "Hands",
	hand = "Hands",
	gloves = "Hands",

	waist = "Waist",
	belt = "Waist",

	feet = "Feet",
	foot = "Feet",
	boots = "Feet",

	ring1 = "Ring1",
	ring01 = "Ring1",
	ringa = "Ring1",

	ring2 = "Ring2",
	ring02 = "Ring2",
	ringb = "Ring2",
}

local function normalize(raw: string): string
	local lower = string.lower(raw)
	lower = string.gsub(lower, "[%s_%-%./]", "")
	return lower
end

local EquipmentSlotSchema = {}

function EquipmentSlotSchema.list(): { EquipmentSlotId }
	local out = table.clone(SLOT_IDS) :: { EquipmentSlotId }
	return out
end

function EquipmentSlotSchema.canonicalize(raw: string): EquipmentSlotId?
	local key = normalize(raw)
	return ALIASES[key]
end

return EquipmentSlotSchema
