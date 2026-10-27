--!strict
-- The mastery tracks a player can progress (docs/planning/progression-direction.md, "Masteries").
--
-- Two families. Attack types are how a character fights -- Magic, Blade, Blunt, Ranged -- and are
-- not one per weapon: a mage casts without a wand, and Blade covers swords and daggers alike.
-- Elements are what an attack carries, independent of the weapon.
--
-- A track's `id` is a key in every player's save (`progression.masteries`), so it must never change
-- once shipped.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BasicAttackProfileTypes = require(ReplicatedStorage.Shared.skills.BasicAttackProfileTypes)

export type TrackFamily = "attack" | "element"

export type Track = {
	id: string,
	displayName: string,
	family: TrackFamily,
	-- ItemGlyphs id drawn for the track.
	glyph: string,
}

local MasteryTracks = {}

local TRACKS: { Track } = {
	{ id = "Blade", displayName = "Blade", family = "attack", glyph = "sword" },
	{ id = "Blunt", displayName = "Blunt", family = "attack", glyph = "fist" },
	{ id = "Magic", displayName = "Magic", family = "attack", glyph = "wand" },
	{ id = "Ranged", displayName = "Ranged", family = "attack", glyph = "bow" },
	{ id = "Fire", displayName = "Fire", family = "element", glyph = "flame" },
	{ id = "Frost", displayName = "Frost", family = "element", glyph = "snowflake" },
}

-- The track whose root form a weapon context uses by default (progression-launch-content.md,
-- "Weapon contexts"). A context is a weapon class, or "unarmed" for empty hands.
local TRACK_FOR_CONTEXT: { [string]: string } = {
	[BasicAttackProfileTypes.UNARMED_CLASS_KEY] = "Blunt",
	sword = "Blade",
	dagger = "Blade",
	axe = "Blade",
	mace = "Blunt",
	wand = "Magic",
	staff = "Magic",
	bow = "Ranged",
}

-- Damage types that are an element, and the track they feed.
local TRACK_FOR_DAMAGE_TYPE: { [string]: string } = {
	Fire = "Fire",
	Frost = "Frost",
}

local byId: { [string]: Track } = {}
for _, track in ipairs(TRACKS) do
	byId[track.id] = track
end

function MasteryTracks.list(): { Track }
	return TRACKS
end

function MasteryTracks.get(id: string): Track?
	return byId[id]
end

-- The track of a weapon context's default form.
function MasteryTracks.forContext(classKey: string): Track?
	local id = TRACK_FOR_CONTEXT[classKey]
	return if id then byId[id] else nil
end

-- The element track a damage type feeds, if it is an element.
function MasteryTracks.forDamageType(damageType: string): Track?
	local id = TRACK_FOR_DAMAGE_TYPE[damageType]
	return if id then byId[id] else nil
end

return MasteryTracks
