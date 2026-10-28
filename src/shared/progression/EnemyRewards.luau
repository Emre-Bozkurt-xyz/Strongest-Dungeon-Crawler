--!strict
-- What an enemy is worth: the character XP its kill shares out, and the mastery value fighting it
-- teaches (progression-direction.md, "Character XP from enemies").
--
-- Modelled on Path of Exile: an enemy inherits its map's area level, and differs from others of
-- that level only by what it is -- its type multiplier (a worm that comes forty at a time is worth a
-- fraction of a skeleton) -- and its rank. Ranks are rolled per spawn or forced by the map builder;
-- bosses are dedicated entities with their own type multiplier, never a promoted normal enemy.
--
-- All numbers are placeholders, to tune with pacing.

local EnemyRewards = {}

export type Rank = "Normal" | "Magic" | "Elite" | "Unique"

-- What a rank multiplies. XP follows PoE's proportions (magic +250%, rare +750%, unique +450%).
local RANKS: { [string]: { xp: number, mastery: number } } = {
	Normal = { xp = 1, mastery = 1 },
	Magic = { xp = 3.5, mastery = 2 },
	Elite = { xp = 8.5, mastery = 4 },
	Unique = { xp = 5.5, mastery = 3 },
}
EnemyRewards.RANKS = RANKS

-- Chance per spawn of a rolled rank. Unique never rolls: it is a rare spawn under specific
-- conditions in specific maps, so the map builder forces it.
local MAGIC_CHANCE = 0.12
local ELITE_CHANCE = 0.03

-- A normal enemy of type multiplier 1 at `areaLevel`.
function EnemyRewards.baseXp(areaLevel: number): number
	return 10 * math.max(1, areaLevel) ^ 1.25
end

function EnemyRewards.baseMasteryValue(areaLevel: number): number
	return 40 * math.max(1, areaLevel) ^ 1.15
end

function EnemyRewards.isRank(value: any): boolean
	return type(value) == "string" and RANKS[value] ~= nil
end

-- Roll a rank for one spawn.
function EnemyRewards.rollRank(random: Random?): Rank
	local roll = if random then random:NextNumber() else math.random()
	if roll < ELITE_CHANCE then
		return "Elite"
	elseif roll < ELITE_CHANCE + MAGIC_CHANCE then
		return "Magic"
	end
	return "Normal"
end

-- Kill XP and mastery value for an enemy. `masteryMultiplier` defaults to `typeMultiplier`; an enemy
-- can teach more than it is worth to kill (a tough, slow brute) or less.
function EnemyRewards.valuesFor(
	areaLevel: number,
	typeMultiplier: number,
	rank: Rank,
	masteryMultiplier: number?
): (number, number)
	local factors = RANKS[rank] or RANKS.Normal
	local xp = EnemyRewards.baseXp(areaLevel) * typeMultiplier * factors.xp
	local mastery = EnemyRewards.baseMasteryValue(areaLevel) * (masteryMultiplier or typeMultiplier) * factors.mastery
	return xp, mastery
end

-- The share of kill XP a character gets for the gap between their level and the area's. Very light
-- by design: within a safe range that widens with level nothing is lost, and beyond it a few percent
-- per level, never below half, so carrying a low-level friend is pointless but playing a little
-- above or below your level costs nothing.
function EnemyRewards.levelPenalty(characterLevel: number, areaLevel: number): number
	local safe = 3 + math.floor(characterLevel / 16)
	local excess = math.max(0, math.abs(characterLevel - areaLevel) - safe)
	return math.max(0.5, 1 - 0.04 * excess)
end

return EnemyRewards
