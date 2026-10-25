--!strict
-- The player's skill slot sets: owned by the server (LoadoutService), kept in the player's save, and
-- mirrored on the client (SkillSlots).

local LoadoutTypes = {}

-- Slots per set. Matches the Skill1..Skill5 input actions.
LoadoutTypes.SLOTS_PER_SET = 5

-- Marks an empty slot. Slots are a dense array rather than a sparse one with nil holes: a sparse
-- array does not survive either DataStore JSON or a remote intact.
LoadoutTypes.EMPTY = ""

-- Longest skill name a slot will hold. Bounds what a client can make the server store.
LoadoutTypes.MAX_SKILL_NAME_LENGTH = 64

export type SlotSet = {
	-- Exactly SLOTS_PER_SET entries; EMPTY where nothing is assigned.
	slots: { string },
}

export type Loadout = {
	activeSet: number,
	sets: { SlotSet },
}

export type LoadoutCommand =
	{ kind: "assign", set: number, slot: number, skill: string }
	| { kind: "clear", set: number, slot: number }
	| { kind: "setActive", set: number }

export type LoadoutResponse = {
	ok: boolean,
	error: string?,
	-- The authoritative loadout after the command, applied or not. Absent only when the player's
	-- data has not loaded.
	loadout: Loadout?,
}

return LoadoutTypes
