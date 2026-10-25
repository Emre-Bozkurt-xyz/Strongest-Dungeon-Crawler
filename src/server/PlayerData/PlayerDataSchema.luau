--!strict
-- The shape of a player's save, and how older saves are brought up to it.
--
-- Everything here outlives the code that wrote it, so a field is never repurposed: retire it and add
-- a new one. A field that is merely missing from an older save is filled from `template()` by
-- ProfileStore's Reconcile and needs no migration; a change to an existing field's shape or meaning
-- does, as a step in `migrations`.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LoadoutTypes = require(ReplicatedStorage.Shared.skills.LoadoutTypes)

local EMPTY = LoadoutTypes.EMPTY

export type MasteryProgress = {
	level: number,
	xp: number,
}

-- Reserved for the progression model in docs/planning/progression-direction.md. Nothing writes these
-- yet; they are in the template so the first save that needs them is not a migration.
export type ProgressionData = {
	-- Keyed by mastery track id ("Fire", "Wand", ...).
	masteries: { [string]: MasteryProgress },
	-- Attuned mastery ids, at most two.
	attunement: { string },
	-- Selected shape node id, keyed by weapon class.
	shapes: { [string]: string },
	-- Selected infusion node id, or "" for none. A string rather than nil so it reads as present.
	infusion: string,
}

export type SavedItem = {
	itemId: string,
	stackSize: number,
	meta: { [string]: any }?,
}

export type SavedInventory = {
	capacity: number,
	-- Dense, one entry per inventory slot: an item uid, or "" for empty.
	slots: { string },
	-- Equip slot name -> item uid.
	equipment: { [string]: string },
	-- Every item referenced above, by uid.
	items: { [string]: SavedItem },
}

-- Only what the player chose. Bonuses from gear are re-derived from what is equipped.
export type SavedAttributes = {
	-- Attribute name -> base value. Missing names keep their default.
	base: { [string]: number }?,
	availablePoints: number?,
}

export type PlayerSaveData = {
	version: number,
	loadout: LoadoutTypes.Loadout,
	progression: ProgressionData,
	inventory: SavedInventory,
	attributes: SavedAttributes,
	-- Set once the starting items have been handed out, so a returning player is not given them
	-- again on every join.
	starterKitGranted: boolean,
}

local PlayerDataSchema = {}

PlayerDataSchema.VERSION = 1

-- `migrations[n]` brings a version-n save to version n + 1, in place.
local migrations: { [number]: (data: any) -> () } = {}

-- The starting kit's slot sets.
function PlayerDataSchema.defaultLoadout(): LoadoutTypes.Loadout
	return {
		activeSet = 1,
		sets = {
			{ slots = { "BasicAttack", "Dash", "DodgeRoll", EMPTY, EMPTY } },
			{ slots = { "TripleStrike", "ManaBall", "CascadingManaBalls", EMPTY, EMPTY } },
		},
	}
end

function PlayerDataSchema.template(): PlayerSaveData
	return {
		version = PlayerDataSchema.VERSION,
		loadout = PlayerDataSchema.defaultLoadout(),
		progression = {
			masteries = {},
			attunement = {},
			shapes = {},
			infusion = "",
		},
		inventory = {
			capacity = 30,
			slots = {},
			equipment = {},
			items = {},
		},
		attributes = {},
		starterKitGranted = false,
	}
end

-- A copy of `value` that a DataStore can hold: strings, booleans, finite numbers, and tables of
-- those keyed by strings or as arrays. Anything else is dropped with a warning naming where it was,
-- rather than failing the whole save.
function PlayerDataSchema.saveable(value: any, path: string?): any
	local kind = type(value)
	if kind == "string" or kind == "boolean" then
		return value
	end
	if kind == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			warn(`PlayerDataSchema: dropped non-finite number at {path or "?"}`)
			return nil
		end
		return value
	end
	if kind == "table" then
		local out = {}
		for key, child in pairs(value) do
			if type(key) == "string" or type(key) == "number" then
				out[key] = PlayerDataSchema.saveable(child, `{path or ""}.{key}`)
			else
				warn(`PlayerDataSchema: dropped {typeof(key)} key at {path or "?"}`)
			end
		end
		return out
	end
	warn(`PlayerDataSchema: dropped {typeof(value)} at {path or "?"}`)
	return nil
end

-- Run before Reconcile, so each step sees the save as its version wrote it.
function PlayerDataSchema.migrate(data: any)
	local version = if type(data.version) == "number" then data.version else PlayerDataSchema.VERSION
	if version > PlayerDataSchema.VERSION then
		-- Written by a newer server (mid-rollout). Left as it is: this server cannot know what the
		-- newer fields mean, and ProfileStore saves them back untouched.
		warn(`PlayerDataSchema: save is version {version}, newer than this server's {PlayerDataSchema.VERSION}`)
		return
	end
	while version < PlayerDataSchema.VERSION do
		local step = migrations[version]
		assert(step, `PlayerDataSchema: no migration from version {version}`)
		step(data)
		version += 1
	end
	data.version = version
end

return PlayerDataSchema
