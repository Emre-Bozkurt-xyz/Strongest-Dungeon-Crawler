--!strict
-- The mastery tracks a player can progress, the level curve they share, and the one rule for
-- whether a set of mastery levels meets a requirement. Shared so the server's unlock checks and the
-- client's mastery canvas agree on every number.
--
-- A track's `id` is a key in every player's save (`progression.masteries`) and in shape
-- requirements, so it must never change once shipped. Weapon tracks only for now: element tracks
-- arrive with infusions (docs/planning/progression-direction.md, build order step 4).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BasicAttackProfileTypes = require(ReplicatedStorage.Shared.skills.BasicAttackProfileTypes)

export type TrackKind = "weapon"

export type Track = {
	id: string,
	displayName: string,
	kind: TrackKind,
	-- The class key whose basic attack shapes make up this track's tree.
	classKey: string,
	-- ItemGlyphs id drawn for the track.
	glyph: string,
}

local MasteryTracks = {}

local TRACKS: { Track } = {
	{
		id = "Unarmed",
		displayName = "Unarmed",
		kind = "weapon",
		classKey = BasicAttackProfileTypes.UNARMED_CLASS_KEY,
		glyph = "fist",
	},
	{ id = "Sword", displayName = "Sword", kind = "weapon", classKey = "sword", glyph = "sword" },
	{ id = "Dagger", displayName = "Dagger", kind = "weapon", classKey = "dagger", glyph = "dagger" },
	{ id = "Wand", displayName = "Wand", kind = "weapon", classKey = "wand", glyph = "wand" },
}

local byId: { [string]: Track } = {}
local byClassKey: { [string]: Track } = {}
for _, track in ipairs(TRACKS) do
	byId[track.id] = track
	byClassKey[track.classKey] = track
end

MasteryTracks.MAX_LEVEL = 30

-- Provisional until the progression design pass settles what feeds mastery: every target a basic
-- attack lands on with a weapon class is one point toward that class's track.
MasteryTracks.XP_PER_HIT = 1

function MasteryTracks.list(): { Track }
	return TRACKS
end

function MasteryTracks.get(id: string): Track?
	return byId[id]
end

function MasteryTracks.forClassKey(classKey: string): Track?
	return byClassKey[classKey]
end

-- XP needed to go from `level` to the next, or nil at the cap. Grows a little faster than linearly so
-- early levels come quickly and later ones mean something.
function MasteryTracks.xpToNext(level: number): number?
	if level >= MasteryTracks.MAX_LEVEL then
		return nil
	end
	return math.floor(20 * (level + 1) ^ 1.5 + 0.5)
end

-- Whether `levels` (track id -> level) meets every mastery level in `requires`.
function MasteryTracks.meets(levels: { [string]: number }, requires: { mastery: { [string]: number }? }?): boolean
	local mastery = requires and requires.mastery
	for track, level in pairs(mastery or {}) do
		if (levels[track] or 0) < level then
			return false
		end
	end
	return true
end

return MasteryTracks
