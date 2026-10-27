--!strict
-- The numbers behind mastery: how much XP a branch holds, where its ranks sit, how total XP becomes
-- a track level, and what a use earns. Pure and shared, so the server's grants and unlocks and the
-- client's canvas read the same values.
--
-- Every number here is a placeholder for the first playable cut (docs/tasks/mastery-model-v2.md)
-- and is expected to be tuned with pacing.
--
-- Model (docs/planning/progression-direction.md, "Mastery XP from use"): XP is saved per branch --
-- the trunk and branches "a" and "b". A track's level comes from its total XP on one curve, so it
-- never depends on how many nodes a tree has. Each branch has a cap; at the cap it is Mastered and
-- takes no more XP.

local MasteryXP = {}

export type BranchId = string

-- Branch XP at which trunk ranks 1 and 2 unlock (rank 0 is the root, always available).
MasteryXP.TRUNK_RANKS = { 30, 120 }
-- Branch XP at which branch ranks 1-4 unlock. Rank 1 needs no XP of its own: it unlocks from the
-- trunk (BRANCH_ENTRY), because a branch only earns XP through a form selected in it.
MasteryXP.BRANCH_RANKS = { 0, 200, 600, 1500 }
-- Trunk XP that opens rank 1 of both branches.
MasteryXP.BRANCH_ENTRY = 120
-- The rank in each branch the joining node needs.
MasteryXP.JOIN_RANK = 3

-- Where each branch is Mastered. Past its last node a branch keeps earning up to here, which is the
-- room continuous in-node scaling grows in.
MasteryXP.TRUNK_CAP = 400
MasteryXP.BRANCH_CAP = 3000

MasteryXP.MAX_LEVEL = 30
-- Total XP at MAX_LEVEL is exactly what a fully Mastered track holds.
local TRACK_CAP = MasteryXP.TRUNK_CAP + 2 * MasteryXP.BRANCH_CAP
local EXPONENT = 2.3
local SCALE = TRACK_CAP / MasteryXP.MAX_LEVEL ^ EXPONENT

-- Training: below this level a use gives a little flat XP, and a training target gives a little
-- more. At and past it, only real fights count.
MasteryXP.TRAINING_CAP_LEVEL = 5
MasteryXP.USE_XP = 1
MasteryXP.TRAINING_HIT_XP = 2

-- One use never gives more than this share of the XP between the track's level and the next.
-- A guard against bugs and exploits, generous enough that normal play never meets it.
MasteryXP.CEILING_SHARE = 0.2

function MasteryXP.capOf(branch: BranchId): number
	return if branch == "trunk" then MasteryXP.TRUNK_CAP else MasteryXP.BRANCH_CAP
end

-- Total XP needed to reach `level`.
function MasteryXP.totalFor(level: number): number
	if level <= 0 then
		return 0
	end
	if level >= MasteryXP.MAX_LEVEL then
		return TRACK_CAP
	end
	return math.floor(SCALE * level ^ EXPONENT + 0.5)
end

function MasteryXP.levelOf(total: number): number
	local level = 0
	while level < MasteryXP.MAX_LEVEL and total >= MasteryXP.totalFor(level + 1) do
		level += 1
	end
	return level
end

export type Progress = {
	level: number,
	-- XP into the current level, and the XP the next level needs; nil `needed` at the top.
	into: number,
	needed: number?,
}

function MasteryXP.progressOf(total: number): Progress
	local level = MasteryXP.levelOf(total)
	if level >= MasteryXP.MAX_LEVEL then
		return { level = level, into = 0, needed = nil }
	end
	local floor = MasteryXP.totalFor(level)
	return { level = level, into = total - floor, needed = MasteryXP.totalFor(level + 1) - floor }
end

function MasteryXP.totalOf(branches: { [BranchId]: number }): number
	local total = 0
	for _, xp in pairs(branches) do
		total += xp
	end
	return total
end

-- Rank reached in a branch from its XP: 0 when none, up to #ranks.
function MasteryXP.rankOf(branch: BranchId, branches: { [BranchId]: number }): number
	local xp = branches[branch] or 0
	if branch == "trunk" then
		local rank = 0
		for index, threshold in ipairs(MasteryXP.TRUNK_RANKS) do
			if xp >= threshold then
				rank = index
			end
		end
		return rank
	end
	if (branches.trunk or 0) < MasteryXP.BRANCH_ENTRY then
		return 0
	end
	local rank = 0
	for index, threshold in ipairs(MasteryXP.BRANCH_RANKS) do
		if xp >= threshold then
			rank = index
		end
	end
	return rank
end

function MasteryXP.isMastered(branch: BranchId, branches: { [BranchId]: number }): boolean
	return (branches[branch] or 0) >= MasteryXP.capOf(branch)
end

-- XP a connecting use earns before the ceiling: the target's value, scaled by how much of its health
-- the hit removed and by the skill's tier.
function MasteryXP.connectXp(targetValue: number, healthShare: number, tier: number): number
	return targetValue * math.clamp(healthShare, 0, 1) * tier
end

-- The most one use may give a track at `total` XP.
function MasteryXP.ceilingFor(total: number): number
	local progress = MasteryXP.progressOf(total)
	return if progress.needed then progress.needed * MasteryXP.CEILING_SHARE else 0
end

return MasteryXP
