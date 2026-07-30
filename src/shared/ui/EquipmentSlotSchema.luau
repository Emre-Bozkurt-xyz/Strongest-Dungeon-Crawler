--!strict
-- Equipment slot display order and normalization helpers for UI/runtime binding.
--
-- The set of legal slots lives in ItemTypes.EquipSlot / ItemEnums.EquipSlot; this module owns only
-- the *order* they are presented in and the alias table mapping loose author/UI spellings onto
-- canonical ids.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemEnums = require(ReplicatedStorage.Shared.items.ItemEnums)
local ItemTypes = require(ReplicatedStorage.Shared.items.ItemTypes)

export type EquipmentSlotId = ItemTypes.EquipSlot

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

-- A slot in the enum with no display position here would validate on items and then not render.
do
	local ordered: { [string]: boolean } = {}
	for _, slotId in ipairs(SLOT_IDS) do
		ordered[slotId] = true
	end
	for _, slotId in ipairs(ItemEnums.listEquipSlots()) do
		assert(ordered[slotId], `EquipmentSlotSchema: slot '{slotId}' exists in ItemEnums but has no display order entry`)
	end
end

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
