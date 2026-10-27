--!strict
-- The character level curve (docs/planning/progression-direction.md, "Experience"): a separate
-- stream from mastery. Total XP is saved; the level is derived from it, so retuning the curve needs
-- no save migration. Shared so the server's grants and the client's STATUS panel agree.
--
-- Front-loaded on purpose: early levels come in minutes to hook a new player, later ones take
-- dedicated effort. Every number is a placeholder to tune with pacing.

local CharacterXP = {}

CharacterXP.MAX_LEVEL = 100
-- Attribute points granted for each level gained.
CharacterXP.POINTS_PER_LEVEL = 3

-- XP to go from `level` to the next, or nil at the cap.
function CharacterXP.xpToNext(level: number): number?
	if level >= CharacterXP.MAX_LEVEL then
		return nil
	end
	return math.floor(30 * level ^ 1.9 + 0.5)
end

-- Total XP needed to reach `level` (level 1 is where everyone starts).
function CharacterXP.totalFor(level: number): number
	local total = 0
	for l = 1, math.min(level, CharacterXP.MAX_LEVEL) - 1 do
		total += CharacterXP.xpToNext(l) :: number
	end
	return total
end

export type Progress = {
	level: number,
	-- XP into the current level, and what the next needs; nil `needed` at the cap.
	into: number,
	needed: number?,
}

function CharacterXP.progressOf(total: number): Progress
	local level = 1
	local remaining = total
	while true do
		local needed = CharacterXP.xpToNext(level)
		if not needed or remaining < needed then
			return { level = level, into = remaining, needed = needed }
		end
		remaining -= needed
		level += 1
	end
end

function CharacterXP.levelOf(total: number): number
	return CharacterXP.progressOf(total).level
end

return CharacterXP
