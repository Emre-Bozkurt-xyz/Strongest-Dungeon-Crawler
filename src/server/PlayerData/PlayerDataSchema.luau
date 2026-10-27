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

-- XP per branch ("trunk", "a", "b"). Levels and unlocks are derived from it (shared/progression),
-- never saved, so retuning a threshold needs no migration.
export type MasteryProgress = {
	branches: { [string]: number },
}

-- The progression model in docs/planning/progression-direction.md. MasteryService writes
-- `masteries`, FormService writes `shapes`, AttunementService writes `attunement`; infusion is
-- reserved until infusions exist.
export type ProgressionData = {
	-- Keyed by mastery track id ("Blade", "Fire", ...).
	masteries: { [string]: MasteryProgress },
	-- Attuned mastery ids.
	attunement: { string },
	-- Selected basic attack profile id, keyed by weapon context (a weapon class, or "unarmed").
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

-- The character level stream, separate from mastery. Only total XP is saved; the level is derived
-- from it (shared/progression/CharacterXP).
export type CharacterData = {
	xp: number,
}

export type PlayerSaveData = {
	version: number,
	loadout: LoadoutTypes.Loadout,
	progression: ProgressionData,
	character: CharacterData,
	inventory: SavedInventory,
	attributes: SavedAttributes,
	-- Set once the starting items have been handed out, so a returning player is not given them
	-- again on every join.
	starterKitGranted: boolean,
}

local PlayerDataSchema = {}

PlayerDataSchema.VERSION = 2

-- `migrations[n]` brings a version-n save to version n + 1, in place.
local migrations: { [number]: (data: any) -> () } = {}

-- v1 -> v2: masteries were one track per weapon class with a level and XP into it; they become
-- attack-type tracks with XP per branch. A v1 track's progress moves into the trunk of the track
-- that replaced it, as the total XP its level represented under the v1 curve, capped at what a
-- trunk holds. v1 only ever existed in development.
local V1_TRACKS: { [string]: string } = {
	Unarmed = "Blunt",
	Sword = "Blade",
	Dagger = "Blade",
	Wand = "Magic",
}
local V1_TRUNK_CAP = 400

migrations[1] = function(data: any)
	local progression = data.progression
	if type(progression) ~= "table" or type(progression.masteries) ~= "table" then
		return
	end
	local old = progression.masteries
	local masteries = {}
	for oldId, entry in pairs(old) do
		local trackId = V1_TRACKS[oldId]
		if trackId and type(entry) == "table" then
			-- v1 curve: 20 * (level + 1) ^ 1.5 XP to go from a level to the next.
			local total = if type(entry.xp) == "number" then entry.xp else 0
			local level = if type(entry.level) == "number" then entry.level else 0
			for l = 0, level - 1 do
				total += math.floor(20 * (l + 1) ^ 1.5 + 0.5)
			end
			local current = masteries[trackId] or { branches = {} }
			current.branches.trunk = math.min(V1_TRUNK_CAP, (current.branches.trunk or 0) + total)
			masteries[trackId] = current
		end
	end
	progression.masteries = masteries
end

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
		character = { xp = 0 },
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
