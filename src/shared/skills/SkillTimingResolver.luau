--!strict
-- Shared timing resolution logic for skills
-- Used by both client (prediction) and server (authoritative)
-- Maps skill tags → stat type → tempo calculation

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StatTypes = require(ReplicatedStorage.Shared.StatTypes)

local SkillTimingResolver = {}

-- Map skill tag → stat that controls tempo for that tag. Keep lower-case keys.
local TAG_STAT_MAP: { [string]: any } = {
	melee = StatTypes.StaticStats.AttackSpeed :: StatTypes.StaticStatType,
	attack = StatTypes.StaticStats.AttackSpeed :: StatTypes.StaticStatType,
	ranged = StatTypes.StaticStats.AttackSpeed :: StatTypes.StaticStatType,
	physical = StatTypes.StaticStats.AttackSpeed :: StatTypes.StaticStatType,
	spell = StatTypes.StaticStats.SpellCastSpeed :: StatTypes.StaticStatType,
	magic = StatTypes.StaticStats.SpellCastSpeed :: StatTypes.StaticStatType,
	cast = StatTypes.StaticStats.SpellCastSpeed :: StatTypes.StaticStatType,
}

local MIN_TEMPO = 0.05
local MAX_TEMPO = 5

-- Resolve which stat type controls timing for a skill based on its tags
local function resolveStatTypeForSkill(skillTags: { string }?): StatTypes.StaticStatType?
	if type(skillTags) ~= "table" then
		return nil
	end
	for _, t in ipairs(skillTags) do
		if type(t) == "string" then
			local key = string.lower(t)
			local mapped = TAG_STAT_MAP[key]
			if mapped ~= nil then
				return mapped :: any
			end
		end
	end
	return nil
end

-- Calculate tempo and duration scale from stat value
-- tempo: speed multiplier (1.0 = normal, 2.0 = twice as fast)
-- durationScale: inverse of tempo (1.0 = normal, 0.5 = half duration)
local function calculateTempo(statValue: number?): (number, number)
	local tempo = 1
	if type(statValue) == "number" and statValue > 0 then
		tempo = statValue
	end
	tempo = math.clamp(tempo, MIN_TEMPO, MAX_TEMPO)
	local durationScale = 1 / tempo
	return tempo, durationScale
end

export type TimingResult = {
	tempo: number, -- Speed multiplier (e.g., 1.5 = 50% faster)
	durationScale: number, -- Duration multiplier (e.g., 0.667 = animations 33% shorter)
	statType: any, -- Which stat was used (AttackSpeed, SpellCastSpeed, etc.)
}

-- Resolve timing for a skill given its tags and a stat lookup function
-- statLookup: function(statType) -> statValue
function SkillTimingResolver.resolve(skillTags: { string }?, statLookup: (any) -> number?): TimingResult
	local statType = resolveStatTypeForSkill(skillTags)
	local statValue: number? = nil
	
	if statType and statLookup then
		statValue = statLookup(statType)
	end
	
	local tempo, durationScale = calculateTempo(statValue)
	
	return {
		tempo = tempo,
		durationScale = durationScale,
		statType = statType,
	}
end

-- Calculate target duration for a base duration given tempo
function SkillTimingResolver.scaleDuration(baseDuration: number, tempo: number): number
	return baseDuration / tempo
end

return SkillTimingResolver
