--!strict
-- Server-side timing resolver wrapper
-- Uses shared SkillTimingResolver with server's authoritative StatsManager

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Server = game:GetService("ServerScriptService").Server

local StatsManager = require(Server.Stats.StatsManager)
local SkillsConfig = require(script.Parent.SkillsConfig)
local SkillTimingResolver = require(ReplicatedStorage.Shared.skills.SkillTimingResolver)

local SkillTimingService = {}

function SkillTimingService.resolve(entityId: string, skillId: string)
	assert(entityId and skillId and type(skillId) == "string", "SkillTimingService.resolve: bad args")
	local skillConfig = SkillsConfig.skills[skillId]
	
	local skillTags = skillConfig and (skillConfig.tags or skillConfig.categories) or nil
	
	-- Create stat lookup function for this entity
	local function statLookup(statType: any): number?
		return StatsManager.getStatValue(entityId, statType)
	end
	
	-- Use shared resolver
	local result = SkillTimingResolver.resolve(skillTags, statLookup)
	
	-- Return in legacy format for compatibility (can be updated later)
	return {
		durationScale = result.durationScale,
		tempo = result.tempo,
		statType = result.statType,
	}
end

return SkillTimingService
